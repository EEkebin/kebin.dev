# Runbook: after a power loss or hard reboot

Symptoms: a subdomain returns 502, or `podman ps` shows a container "Up" that does not answer.

1. Check the mount and GPU on the media VM:
   ```
   mountpoint /mnt/storage && df -h /mnt/storage
   nvidia-smi --query-gpu=name --format=csv,noheader
   ```
   If the share is missing, `mount -a`. Containers that started before the mount see an empty `/data`; restart them after mounting.

2. Find zombie containers. Podman can list a container as running while its process died with the power. The only reliable test is exec:
   ```
   cd /srv/media
   for c in $(podman ps -a --format '{{.Names}}'); do podman exec "$c" true >/dev/null 2>&1 || echo "DEAD $c"; done
   ```
3. Recreate each dead one (data is on bind mounts, nothing is lost):
   ```
   podman rm -f <name>; podman-compose up -d <name>
   ```
   Also `podman start` anything shown as Exited.

4. Confirm every port answers:
   ```
   for p in 8096 5055 9696 8989 7878 8686 6767 8080 8265 4533 8090 8081; do printf "%s:%s " $p $(curl -s -o /dev/null -m 5 -w %{http_code} http://127.0.0.1:$p/); done; echo
   ```

Autostart ordering is handled by `systemd/podman-restart.service.d/wait-for-storage.conf` (waits for `mnt-storage.mount`). A UPS on the NAS and this VM is the real fix.

Shortcut for the zombie sweep: `sudo /srv/media/revive.sh` (`--check` to only list). It tests the conmon pid of every container, which is the only reliable liveness signal; `podman exec` still succeeds on a dead one.
