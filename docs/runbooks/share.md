# Runbook: share.kebin.dev

Browser-to-browser file sending, LocalSend-style, no login. Code: `infra/web/share/` (`share.py` server, `index.html` page), service `kebin-share.service` on the web VM (127.0.0.1:8766, DynamicUser, state in `/var/lib/kebin-share/clients.json`), nginx `share.kebin.dev.conf`. Installed and restarted by `deploy.sh`.

- **Identity**: each browser gets a random name and a 4-digit PIN, kept in its localStorage (id + token) and on the server (id, name, PIN, token hash). Unseen for 90 days frees the PIN. Click the name to rename.
- **Who sees whom**: open pages on the same public IPv4, or the same IPv6 /64, list each other. Everyone else is reached by PIN. A device on IPv6 and one on IPv4-only in the same house will not list each other; the PIN still works.
- **Sending**: an offer (names, sizes) goes to the receiver, who must Accept. Then WebRTC data channel, browser to browser (STUN: Cloudflare, Google; no TURN). If the direct connection does not open within 12 s, or a file is over 1 GB (the receiver holds a direct file in memory until it is complete), the file is streamed through the server instead: `PUT/GET /api/relay/<tid>/<i>`, only for an accepted offer, only by its sender, nothing written to disk, 16 MB in flight, at most 6 relays at once. Relayed files use the home line in both directions.
- **Abuse limits**: nginx 5 req/s per IP (burst 40) on join/signal/rename; the server allows 20 offers per minute per device and 40 per IP, 30 joins per 10 minutes per IP. Every transfer needs the receiver's click.
- **Restart**: `sudo systemctl restart kebin-share`. Open pages reconnect on their own and keep their PIN.
- **HTTP/3 is off for this host** (`snippets/no-h3.conf` sends `Alt-Svc: clear`): over QUIC the relay upload was cut off after ~0.5 MB and the event stream stalled, while HTTP/1.1 and HTTP/2 moved 40 MB byte-identical. The QUIC listener stays in the server block so a pooled h3 request is not misrouted.
