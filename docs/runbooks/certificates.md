# Runbook: certificates

One Let's Encrypt wildcard certificate for `kebin.dev` and `*.kebin.dev`, issued by acme.sh on the web VM through a Porkbun DNS-01 challenge. Files: `/etc/nginx/ssl/kebin.dev/{fullchain,privkey}.pem`.

- **Renewal** is automatic. acme.sh's cron runs four times a day and renews about 30 days before expiry, then reloads nginx. Check: `openssl x509 -in /etc/nginx/ssl/kebin.dev/fullchain.pem -noout -enddate`.
- **Force a renewal:** `/root/.acme.sh/acme.sh --renew --ecc -d kebin.dev --force`.
- **Porkbun keys** are stored by acme.sh in `/root/.acme.sh/account.conf`. Rotating them at Porkbun means updating that file (`SAVED_PORKBUN_API_KEY`, `SAVED_PORKBUN_SECRET_API_KEY`) and the API-access toggle stays on for the domain.
- **Another domain:** `acme.sh --issue --dns dns_porkbun -d example.com -d '*.example.com' --keylength ec-256`, then `--install-cert` into `/etc/nginx/ssl/example.com/` and reference it from that domain's server blocks. Enable API access on the domain at Porkbun first.
