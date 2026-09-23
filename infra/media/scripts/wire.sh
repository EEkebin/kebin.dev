#!/bin/bash
# Connect the media apps to each other after first boot. Idempotent: re-running updates in place.
# Usage (as root on the media VM):  ./wire.sh            do everything
#                                   ./wire.sh --credentials   just print the logins
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST=/srv/media
. "$DEST/.env"
U=${JF_ADMIN_USER:-admin}
J='Content-Type: application/json'
key() { grep -oP "(?<=<ApiKey>)[^<]+" "$DEST/config/$1/config.xml"; }
say() { echo; echo "== $*"; }
jf_token() {
  curl -s -H "$J" -H 'Authorization: MediaBrowser Client="wire", Device="media-vm", DeviceId="wire-1", Version="1.0"' \
    -d "{\"Username\":\"$U\",\"Pw\":\"$JF_ADMIN_PASSWORD\"}" http://127.0.0.1:8096/Users/AuthenticateByName | python3 -c 'import sys,json; print(json.load(sys.stdin)["AccessToken"])'
}

if [ "${1:-}" = "--credentials" ]; then
  cat <<EOF
stream.kebin.dev       $U / $JF_ADMIN_PASSWORD   (Seerr uses the same login)
sonarr/radarr/lidarr/prowlarr/bazarr   $U / $ARR_PASSWORD
qbittorrent.kebin.dev  $U / $QBT_PASSWORD
music.kebin.dev        $U / $ND_ADMIN_PASSWORD
files.kebin.dev        $U / $FB_ADMIN_PASSWORD
cloud.kebin.dev        $U / $NC_ADMIN_PASSWORD
EOF
  exit 0
fi

say "wait for the apps"
for p in 8096 5055 9696 8989 7878 8686 6767 8080 4533; do
  for i in $(seq 1 60); do curl -s -o /dev/null -m 3 "http://127.0.0.1:$p/" && break; sleep 3; done
done
SONARR=$(key sonarr); RADARR=$(key radarr); LIDARR=$(key lidarr); PROWLARR=$(key prowlarr)

say "qBittorrent: login, paths, categories"
QB=http://127.0.0.1:8080; CJ=$(mktemp)
TMP=$(podman logs qbittorrent 2>&1 | grep -oP 'temporary password.*?: \K\S+' | tail -1 || true)
curl -s -c "$CJ" -d "username=$U&password=$QBT_PASSWORD" $QB/api/v2/auth/login | grep -q Ok. || curl -s -c "$CJ" -d "username=admin&password=$TMP" $QB/api/v2/auth/login >/dev/null
curl -s -b "$CJ" --data-urlencode "json={\"web_ui_username\":\"$U\",\"web_ui_password\":\"$QBT_PASSWORD\",\"web_ui_host_header_validation\":false,\"save_path\":\"/data/Downloads\",\"temp_path_enabled\":true,\"temp_path\":\"/data/Downloads/incomplete\",\"auto_tmm_enabled\":true,\"category_changed_tmm_enabled\":true,\"save_path_changed_tmm_enabled\":true,\"listen_port\":6881,\"upnp\":false,\"web_ui_max_auth_fail_count\":50}" $QB/api/v2/app/setPreferences
for c in movies tv music; do curl -s -b "$CJ" -d "category=$c&savePath=/data/Downloads/$c" $QB/api/v2/torrents/createCategory >/dev/null; done
rm -f "$CJ"; echo "ok"

say "Sonarr / Radarr / Lidarr: login, root folder, download client, Jellyfin refresh hook"
JFTOK=$(jf_token)
JFKEY=$(curl -s -H "Authorization: MediaBrowser Client=\"wire\", Device=\"media-vm\", DeviceId=\"wire-1\", Version=\"1.0\", Token=\"$JFTOK\"" http://127.0.0.1:8096/Auth/Keys | python3 -c 'import sys,json; ks=[k for k in json.load(sys.stdin)["Items"] if k["AppName"]=="arr-stack"]; print(ks[0]["AccessToken"] if ks else "")')
if [ -z "$JFKEY" ]; then
  curl -s -o /dev/null -X POST -H "Authorization: MediaBrowser Client=\"wire\", Device=\"media-vm\", DeviceId=\"wire-1\", Version=\"1.0\", Token=\"$JFTOK\"" "http://127.0.0.1:8096/Auth/Keys?app=arr-stack"
  JFKEY=$(curl -s -H "Authorization: MediaBrowser Client=\"wire\", Device=\"media-vm\", DeviceId=\"wire-1\", Version=\"1.0\", Token=\"$JFTOK\"" http://127.0.0.1:8096/Auth/Keys | python3 -c 'import sys,json; print([k for k in json.load(sys.stdin)["Items"] if k["AppName"]=="arr-stack"][0]["AccessToken"])')
fi
for app in "sonarr 8989 v3 /data/TV tvCategory tv" "radarr 7878 v3 /data/Movies movieCategory movies" "lidarr 8686 v1 /data/Music musicCategory music"; do
  set -- $app
  python3 - "$1" "$2" "$3" "$4" "$5" "$6" "$(key $1)" "$U" "$ARR_PASSWORD" "$QBT_PASSWORD" "$JFKEY" <<'PY'
import sys, json, urllib.request
name, port, ver, root, catfield, cat, key, user, arrpw, qbpw, jfkey = sys.argv[1:]
B = f"http://127.0.0.1:{port}/api/{ver}"; H = {"X-Api-Key": key, "Content-Type": "application/json"}
def req(m, p, b=None):
    r = urllib.request.Request(B + p, data=None if b is None else json.dumps(b).encode(), method=m, headers=H)
    try:
        with urllib.request.urlopen(r, timeout=60) as x: t = x.read(); return json.loads(t) if t else None
    except urllib.error.HTTPError as e: return {"error": e.read().decode()[:160]}
c = req("GET", "/config/host"); c.update({"authenticationMethod": "forms", "authenticationRequired": "enabled", "username": user, "password": arrpw, "passwordConfirmation": arrpw}); req("PUT", "/config/host", c)
if not any(f["path"] == root for f in req("GET", "/rootfolder")):
    body = {"path": root}
    if name == "lidarr":
        body.update({"name": "Music", "defaultQualityProfileId": req("GET", "/qualityprofile")[0]["id"], "defaultMetadataProfileId": req("GET", "/metadataprofile")[0]["id"], "defaultMonitorOption": "all", "defaultNewItemMonitorOption": "all", "defaultTags": []})
    req("POST", "/rootfolder", body)
dl = {"enable": True, "protocol": "torrent", "priority": 1, "removeCompletedDownloads": True, "removeFailedDownloads": True, "name": "qBittorrent", "implementation": "QBittorrent", "configContract": "QBittorrentSettings", "tags": [],
      "fields": [{"name": "host", "value": "qbittorrent"}, {"name": "port", "value": 8080}, {"name": "useSsl", "value": False}, {"name": "urlBase", "value": ""}, {"name": "username", "value": user}, {"name": "password", "value": qbpw}, {"name": catfield, "value": cat}, {"name": "initialState", "value": 0}]}
ex = [d for d in req("GET", "/downloadclient") if d["implementation"] == "QBittorrent"]
req("PUT", f"/downloadclient/{ex[0]['id']}?forceSave=true", {**dl, "id": ex[0]["id"]}) if ex else req("POST", "/downloadclient?forceSave=true", dl)
if not any(n["name"] == "Jellyfin" for n in req("GET", "/notification")):
    n = {"name": "Jellyfin", "implementation": "MediaBrowser", "configContract": "MediaBrowserSettings", "tags": [], "onGrab": False, "onDownload": True, "onUpgrade": True, "onRename": True, "onHealthIssue": False,
         "fields": [{"name": "host", "value": "jellyfin"}, {"name": "port", "value": 8096}, {"name": "useSsl", "value": False}, {"name": "apiKey", "value": jfkey}, {"name": "notify", "value": False}, {"name": "updateLibrary", "value": True}]}
    n.update({"sonarr": {"onSeriesDelete": True, "onEpisodeFileDelete": True, "onImportComplete": True}, "radarr": {"onMovieDelete": True, "onMovieFileDelete": True}, "lidarr": {"onReleaseImport": True, "onTrackRetag": True, "onArtistDelete": True, "onAlbumDelete": True}}[name])
    req("POST", "/notification", n)
print(name, "ok")
PY
done

say "Prowlarr: login, app sync, FlareSolverr proxy"
python3 - "$PROWLARR" "$SONARR" "$RADARR" "$LIDARR" "$U" "$ARR_PASSWORD" <<'PY'
import sys, json, urllib.request
pk, sk, rk, lk, user, pw = sys.argv[1:]
B = "http://127.0.0.1:9696/api/v1"; H = {"X-Api-Key": pk, "Content-Type": "application/json"}
def req(m, p, b=None):
    r = urllib.request.Request(B + p, data=None if b is None else json.dumps(b).encode(), method=m, headers=H)
    try:
        with urllib.request.urlopen(r, timeout=60) as x: t = x.read(); return json.loads(t) if t else None
    except urllib.error.HTTPError as e: return {"error": e.read().decode()[:160]}
c = req("GET", "/config/host"); c.update({"authenticationMethod": "forms", "authenticationRequired": "enabled", "username": user, "password": pw, "passwordConfirmation": pw}); req("PUT", "/config/host", c)
have = {a["name"] for a in req("GET", "/applications")}
for name, url, key, cats in [("Sonarr", "http://sonarr:8989", sk, [5000, 5010, 5020, 5030, 5040, 5045, 5050, 5090]), ("Radarr", "http://radarr:7878", rk, [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060, 2070, 2080, 2090]), ("Lidarr", "http://lidarr:8686", lk, [3000, 3010, 3020, 3030, 3040, 3050, 3060])]:
    if name in have: continue
    req("POST", "/applications", {"name": name, "syncLevel": "fullSync", "implementation": name, "configContract": f"{name}Settings", "tags": [], "fields": [{"name": "prowlarrUrl", "value": "http://prowlarr:9696"}, {"name": "baseUrl", "value": url}, {"name": "apiKey", "value": key}, {"name": "syncCategories", "value": cats}]})
tags = {t["label"]: t["id"] for t in req("GET", "/tag")}
tag = tags.get("flaresolverr") or req("POST", "/tag", {"label": "flaresolverr"})["id"]
if not any(p["name"] == "FlareSolverr" for p in req("GET", "/indexerProxy")):
    req("POST", "/indexerProxy", {"name": "FlareSolverr", "implementation": "FlareSolverr", "configContract": "FlareSolverrSettings", "tags": [tag], "fields": [{"name": "host", "value": "http://flaresolverr:8191/"}, {"name": "requestTimeout", "value": 60}]})
print("prowlarr ok")
PY

say "Jellyfin: first-run wizard, libraries, NVENC"
python3 - "$U" "$JF_ADMIN_PASSWORD" <<'PY'
import sys, json, urllib.request, time
user, pw = sys.argv[1:]
B = "http://127.0.0.1:8096"; A = 'MediaBrowser Client="wire", Device="media-vm", DeviceId="wire-1", Version="1.0"'
def call(p, body=None, tok=None):
    d = None if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode())
    r = urllib.request.Request(B + p, data=d, method="POST" if d is not None else "GET", headers={"Content-Type": "application/json", "Authorization": A + (f', Token="{tok}"' if tok else "")})
    try:
        with urllib.request.urlopen(r, timeout=60) as x: t = x.read(); return (json.loads(t) if t else None), x.status
    except urllib.error.HTTPError as e: return None, e.code
r, s = call("/Startup/Configuration", {"UICulture": "en-US", "MetadataCountryCode": "US", "PreferredMetadataLanguage": "en"})
if s == 204:
    call("/Startup/User"); call("/Startup/User", {"Name": user, "Password": pw}); call("/Startup/RemoteAccess", {"EnableRemoteAccess": True, "EnableAutomaticPortMapping": False}); call("/Startup/Complete", b"")
tok = call("/Users/AuthenticateByName", {"Username": user, "Pw": pw})[0]["AccessToken"]
have = {v["Name"] for v in call("/Library/VirtualFolders", tok=tok)[0]}
for name, ctype, path in [("Movies", "movies", "/data/Movies"), ("TV", "tvshows", "/data/TV"), ("Music", "music", "/data/Music"), ("Books", "books", "/data/Books"), ("Discover", "mixed", "/jellybridge")]:
    if name not in have: call(f"/Library/VirtualFolders?name={name}&collectionType={ctype}&refreshLibrary=true", {"LibraryOptions": {"PathInfos": [{"Path": path}], "EnableRealtimeMonitor": False, "SaveLocalMetadata": False}}, tok=tok)
u = call("/Users/Me", tok=tok)[0]; cfg = u["Configuration"]; cfg.update({"AudioLanguagePreference": "eng", "SubtitleLanguagePreference": "eng"}); call(f"/Users/{u['Id']}/Configuration", cfg, tok=tok)
print("jellyfin ok (libraries:", sorted(have | {"Movies", "TV", "Music", "Books", "Discover"}), ")")
PY
# NVENC lives in encoding.xml (the REST endpoint rejects it on Jellyfin 12)
python3 - <<'PY'
import xml.etree.ElementTree as ET, subprocess
p = "/srv/media/config/jellyfin/encoding.xml"; t = ET.parse(p); r = t.getroot()
def setv(tag, val):
    e = r.find(tag)
    if e is None: e = ET.SubElement(r, tag)
    e.text = val
changed = r.findtext("HardwareAccelerationType") != "nvenc"
for tag, val in {"HardwareAccelerationType": "nvenc", "EnableHardwareEncoding": "true", "AllowHevcEncoding": "true", "AllowAv1Encoding": "false", "EnableEnhancedNvdecDecoder": "true", "EnableDecodingColorDepth10Hevc": "true", "EnableDecodingColorDepth10Vp9": "true", "EnableTonemapping": "true", "TranscodingTempPath": "/cache/transcodes", "EnableThrottling": "true"}.items(): setv(tag, val)
hd = r.find("HardwareDecodingCodecs") or ET.SubElement(r, "HardwareDecodingCodecs")
for c in list(hd): hd.remove(c)
for c in ["h264", "hevc", "mpeg2video", "vc1", "vp9"]: ET.SubElement(hd, "string").text = c
t.write(p, xml_declaration=True, encoding="utf-8"); subprocess.run(["chown", "1000:1000", p])
if changed: subprocess.run(["podman", "restart", "jellyfin"]); print("nvenc enabled, jellyfin restarted")
PY

say "Bazarr"
BK=$(grep -m1 -oP '(?<=apikey: )\S+' "$DEST/config/bazarr/config/config.yaml")
curl -s -o /dev/null -w "bazarr %{http_code}\n" -H "X-API-KEY: $BK" -X POST http://127.0.0.1:6767/api/system/settings \
  -d "settings-general-use_sonarr=true" -d "settings-sonarr-ip=sonarr" -d "settings-sonarr-port=8989" -d "settings-sonarr-base_url=/" -d "settings-sonarr-ssl=false" -d "settings-sonarr-apikey=$SONARR" \
  -d "settings-general-use_radarr=true" -d "settings-radarr-ip=radarr" -d "settings-radarr-port=7878" -d "settings-radarr-base_url=/" -d "settings-radarr-ssl=false" -d "settings-radarr-apikey=$RADARR" \
  -d "settings-general-serie_default_enabled=true" -d "settings-general-movie_default_enabled=true" \
  -d "settings-auth-type=form" -d "settings-auth-username=$U" -d "settings-auth-password=$ARR_PASSWORD"

say "Recyclarr: TRaSH profiles"
mkdir -p "$DEST/config/recyclarr/configs"
sed "s/__API_KEY__/$SONARR/" "$HERE/../config/recyclarr/web-1080p.yml.tmpl"   > "$DEST/config/recyclarr/configs/web-1080p.yml"
sed "s/__API_KEY__/$RADARR/" "$HERE/../config/recyclarr/hd-bluray-web.yml.tmpl" > "$DEST/config/recyclarr/configs/hd-bluray-web.yml"
chown -R 1000:1000 "$DEST/config/recyclarr"
podman exec recyclarr recyclarr sync 2>&1 | grep -E '\[ERR\]|Completed' | tail -4

say "Seerr: Jellyfin link, Radarr and Sonarr with TRaSH profiles"
python3 - "$U" "$JF_ADMIN_PASSWORD" "$SONARR" "$RADARR" <<'PY'
import sys, json, urllib.request, http.cookiejar
user, pw, sk, rk = sys.argv[1:]
cj = http.cookiejar.CookieJar(); op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
def j(url, body=None, method=None, headers={}):
    d = None if body is None else json.dumps(body).encode()
    r = urllib.request.Request(url, data=d, method=method or ("POST" if d is not None else "GET"), headers={"Content-Type": "application/json", **headers})
    try:
        with op.open(r, timeout=60) as x: t = x.read(); return json.loads(t) if t else None
    except urllib.error.HTTPError as e: return {"error": e.read().decode()[:160]}
S = "http://127.0.0.1:5055/api/v1"
r = j(S + "/auth/jellyfin", {"username": user, "password": pw, "hostname": "jellyfin", "port": 8096, "useSsl": False, "urlBase": "", "serverType": 2})
if "error" in (r or {}): j(S + "/auth/jellyfin", {"username": user, "password": pw})
j(S + "/settings/main", {"applicationUrl": "https://seerr.kebin.dev"})
def prof(base, key, want):
    ps = j(base + "/qualityprofile", headers={"X-Api-Key": key}); m = [p for p in ps if p["name"] == want] or ps; return m[0]["id"], m[0]["name"]
rid, rname = prof("http://127.0.0.1:7878/api/v3", rk, "HD Bluray + WEB"); sid, sname = prof("http://127.0.0.1:8989/api/v3", sk, "WEB-1080p")
radarr = {"name": "Radarr", "hostname": "radarr", "port": 7878, "apiKey": rk, "useSsl": False, "baseUrl": "", "activeProfileId": rid, "activeProfileName": rname, "activeDirectory": "/data/Movies", "is4k": False, "minimumAvailability": "released", "isDefault": True, "externalUrl": "https://radarr.kebin.dev", "syncEnabled": True, "preventSearch": False, "tags": []}
sonarr = {"name": "Sonarr", "hostname": "sonarr", "port": 8989, "apiKey": sk, "useSsl": False, "baseUrl": "", "activeProfileId": sid, "activeProfileName": sname, "activeDirectory": "/data/TV", "activeAnimeProfileId": sid, "activeAnimeProfileName": sname, "activeAnimeDirectory": "/data/TV", "is4k": False, "enableSeasonFolders": True, "isDefault": True, "externalUrl": "https://sonarr.kebin.dev", "syncEnabled": True, "preventSearch": False, "tags": [], "animeTags": []}
for kind, body in (("radarr", radarr), ("sonarr", sonarr)):
    ex = j(S + f"/settings/{kind}")
    if ex: j(S + f"/settings/{kind}/{ex[0]['id']}", body, "PUT")
    else: j(S + f"/settings/{kind}", body)
j(S + "/settings/initialize"); print("seerr ok")
PY

say "Navidrome admin"
curl -s -o /dev/null -w "navidrome %{http_code}\n" -H "$J" -d "{\"username\":\"$U\",\"password\":\"$ND_ADMIN_PASSWORD\"}" http://127.0.0.1:4533/auth/createAdmin

say "Nextcloud: external storage (read-only), tuning"
OCC="podman exec -u www-data nextcloud php occ"
$OCC app:enable files_external >/dev/null 2>&1
$OCC files_external:list --output=json 2>/dev/null | grep -q '"/storage"' || $OCC files_external:create storage local null::null -c datadir=/storage >/dev/null
SID=$($OCC files_external:list --output=json | python3 -c "import sys,json; print([m['mount_id'] for m in json.load(sys.stdin) if m['mount_point'].strip('/')=='storage'][0])")
$OCC files_external:option "$SID" readonly true; $OCC files_external:option "$SID" filesystem_check_changes 1
$OCC config:system:set default_phone_region --value=US >/dev/null; $OCC config:system:set maintenance_window_start --type=integer --value=9 >/dev/null
$OCC app:disable password_policy >/dev/null 2>&1; $OCC background:cron >/dev/null; echo "nextcloud ok"

say "done"
echo "logins: $HERE/wire.sh --credentials"
