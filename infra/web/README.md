# Web VM (10.0.10.20)

Ubuntu 26.04. nginx from the official nginx.org repo (stable line, HTTP/3 built in). Ports 80/443 TCP and 443 UDP are forwarded from the router to this host.

## nginx install

```
apt-get install -y curl gnupg2 ca-certificates lsb-release ubuntu-keyring
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list
printf 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n' > /etc/apt/preferences.d/99nginx
apt-get update && apt-get install -y nginx
rm -f /etc/nginx/conf.d/default.conf
mkdir -p /etc/nginx/snippets /var/www/kebin.dev
```

`nginx -V` must list `--with-http_v3_module`.

## Certificates (acme.sh, Let's Encrypt, DNS-01 via Porkbun)

```
apt-get install -y cron socat
curl -fsSL https://get.acme.sh | sh
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
export PORKBUN_API_KEY=pk1_...  PORKBUN_SECRET_API_KEY=sk1_...   # from Porkbun > API Access; enable API on the domain too
/root/.acme.sh/acme.sh --issue --dns dns_porkbun -d kebin.dev -d '*.kebin.dev' --keylength ec-256
mkdir -p /etc/nginx/ssl/kebin.dev
/root/.acme.sh/acme.sh --install-cert --ecc -d kebin.dev \
  --key-file /etc/nginx/ssl/kebin.dev/privkey.pem --fullchain-file /etc/nginx/ssl/kebin.dev/fullchain.pem \
  --reloadcmd "systemctl reload nginx"
```

acme.sh installs its own cron entry and renews about 30 days before expiry. The Porkbun keys are stored by acme.sh in `/root/.acme.sh/account.conf` and nowhere in this repo.

## Secrets on the web VM (not in the repo)

`/etc/nginx/secrets/`, root:nginx 640:

| File | Used by | Content |
|---|---|---|
| `ai-key-map.conf` | `00-map.conf` (http context) | `map $http_authorization $ai_key_ok { default 0; "Bearer <key>" 1; }` — the ai.kebin.dev / search.kebin.dev API key |
| `ai-key-subfilter.conf` | `kebin.dev.conf`, the `/cli/` page | `sub_filter "__AIBOX_KEY__" "<key>"; sub_filter_once off; sub_filter_types text/html;` |
| `vrc-key.conf` | `vr.kebin.dev.conf` `/admin/api/` | `proxy_set_header X-Admin-Key "<key>"; proxy_set_header Authorization 'MediaBrowser Token="<key>"';` |

Rotate the API key by editing the first two files and `systemctl reload nginx`; the CLI page shows the new key after a fresh login.

## Layout

- `nginx/conf.d/00-default.conf` drops any hostname without its own block (returns 444) on 80 and 443.
- `nginx/conf.d/00-map.conf` WebSocket upgrade map.
- `nginx/conf.d/<name>.kebin.dev.conf` one file per subdomain, all reverse proxies to the media VM except `kebin.dev.conf` which serves `site/` and proxies `/api/status` to the status service.
- `nginx/snippets/tls.conf` protocols, ciphers, Alt-Svc for HTTP/3, HSTS. `snippets/proxy.conf` headers and timeouts for the proxies.
- `status/status.py` reachability endpoint on 127.0.0.1:8765, run by `kebin-status.service` as `nobody`. Add a service by editing the `SERVICES` dict.
- `deploy.sh` idempotent deploy of everything above.

## Verify HTTP/3

`curl -sI https://kebin.dev | grep -i alt-svc` shows `h3=":443"`. Any HTTP/3 capable client (Chrome, curl with ngtcp2) negotiates it on the second request.
