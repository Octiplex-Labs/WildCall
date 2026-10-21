#!/bin/bash
# Sign every pack in dist/packs/source/ and rebuild dist/packs/index.json.
#
# Usage:
#   WILDCALL_SIGN_KEY=<64-hex Octiplex private key> Tools/wildcall-sign/publish-packs.sh
#
# For each <id>.source.json, writes dist/packs/<id>-<version>.wildcallpack
# (the URL the index points to), removes older versions of that pack, then
# lists every signed pack in index.json. Commit dist/packs/ and push to
# main: the app syncs from GitHub raw.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIST="$ROOT/dist/packs"
SOURCE="$DIST/source"
SIGN="$ROOT/Tools/wildcall-sign/sign-and-bundle.swift"
RAW="https://raw.githubusercontent.com/Octiplex-Labs/WildCall/main/dist/packs"

if [ -z "${WILDCALL_SIGN_KEY:-}" ]; then
    echo "error: set WILDCALL_SIGN_KEY (64 hex chars)" >&2
    exit 1
fi

for manifest in "$SOURCE"/*.source.json; do
    id=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$manifest")
    version=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$manifest")
    swift "$SIGN" "$manifest" > /dev/null
    base="$(basename "$manifest" .source.json)"
    rm -f "$DIST/$id"-*.wildcallpack
    mv "$SOURCE/$base.wildcallpack" "$DIST/$id-$version.wildcallpack"
    rm -f "$SOURCE/$base.sig"
    echo "signed $id $version"
done

python3 -I - "$SOURCE" "$DIST/index.json" "$RAW" <<'EOF'
import glob, json, os, sys
from datetime import datetime, timezone
source, index_path, raw = sys.argv[1:]
packs = []
for path in sorted(glob.glob(os.path.join(source, "*.source.json"))):
    m = json.load(open(path, encoding="utf-8"))
    packs.append({
        "id": m["id"],
        "version": m["version"],
        "country": m["country"],
        "kind": m["kind"],
        "url": f"{raw}/{m['id']}-{m['version']}.wildcallpack",
    })
index = {
    "version": 1,
    "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "packs": packs,
}
with open(index_path, "w", encoding="utf-8") as fh:
    json.dump(index, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
print(f"index.json: {len(packs)} packs")
EOF
