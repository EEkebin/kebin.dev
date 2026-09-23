# Runbook: add a service

1. **Compose.** Add the container to `infra/media/compose.yml` with a fully qualified image name, `PUID/PGID` or `user: "1000:1000"`, config under `/srv/media/config/<name>`, and a host port. Media goes under `/mnt/storage/Media` only; never mount the whole share into an automation container.
   ```
   cd /srv/media && podman-compose up -d <name>
   ```
2. **DNS.** Create an A record `<name>.kebin.dev` at Porkbun pointing at the current WAN IP (`curl -4 https://api.ipify.org`). The wildcard certificate already covers it.
3. **nginx.** Copy an existing block, e.g. `infra/web/nginx/conf.d/music.kebin.dev.conf`, rename the `server_name` and the port in `proxy_pass`. Large uploads need `client_max_body_size 0; proxy_request_buffering off;` inside the server block.
4. **Deploy.** Commit, then on the web VM `sudo /srv/kebin.dev/infra/web/deploy.sh`.
5. **Homepage (optional).** Add a card to `site/index.html` and the probe URL to `SERVICES` in `infra/web/status/status.py`, deploy again.
6. **Docs.** Add a row to `docs/ports.md` and the table in `infra/media/README.md`.
