#!/bin/sh
set -eu
T=$(cat /root/.secrets/github-jynx-ios); R=https://api.github.com/repos/salw2e/jynx-ios
RUN=$(curl -sf -H "Authorization: Bearer $T" "$R/actions/workflows/modvoice.yml/runs?status=success&branch=main&per_page=1" | python3 -c 'import json,sys; r=json.load(sys.stdin)["workflow_runs"][0]; print(r["id"], r["run_number"], r["head_sha"][:7])')
set -- $RUN
URL=$(curl -sf -H "Authorization: Bearer $T" "$R/actions/runs/$1/artifacts" | python3 -c 'import json,sys; print([a for a in json.load(sys.stdin)["artifacts"] if a["name"]=="ModVoice-ipa"][0]["archive_download_url"])')
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
curl -sfL -H "Authorization: Bearer $T" -o "$TMP/a.zip" "$URL"
KEY=$(grep '^MODVOICE_KEY=' /opt/modvoice/.env | cut -d= -f2)
python3 - "$TMP" "$KEY" <<'PY'
import plistlib, sys, zipfile
tmp, key = sys.argv[1], sys.argv[2]
src = zipfile.ZipFile(f"{tmp}/a.zip").open("ModVoice.ipa")
inp = zipfile.ZipFile(src)
plists = ["Payload/ModVoice.app/Info.plist", "Payload/ModVoice.app/PlugIns/Keyboard.appex/Info.plist"]
with zipfile.ZipFile(f"{tmp}/ModVoice.ipa", "w", zipfile.ZIP_DEFLATED) as out:
    for item in inp.infolist():
        data = inp.read(item.filename)
        if item.filename in plists:
            p = plistlib.loads(data)
            p["ModVoiceKey"] = key
            data = plistlib.dumps(p, fmt=plistlib.FMT_BINARY)
        out.writestr(item, data)
for plist in plists:
    assert plistlib.loads(zipfile.ZipFile(f"{tmp}/ModVoice.ipa").read(plist))["ModVoiceKey"] == key
PY
install -m 644 "$TMP/ModVoice.ipa" /var/www/jynx-download/ModVoice.ipa.new && mv /var/www/jynx-download/ModVoice.ipa.new /var/www/jynx-download/ModVoice.ipa
echo "published build #$2 ($3), $(stat -c %s /var/www/jynx-download/ModVoice.ipa) bytes"
