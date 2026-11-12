#!/bin/bash
# Copy the publishable tree to the public repository folder (D45, docs/release.md §2). The private history stays here.
# usage: export_public.sh [dest]   default build/public-repo. Then run scripts/check_release.py on it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/build/public-repo}"
# Never published: owner data, test logs of the owner's iPad, third-party screenshots, the owner's icon.
EXCLUDE='^(local/|docs/STATUS\.md$|docs/design/reference/|docs/research/|tests/artifacts/|tests/device/joint_padbook\.py$|assets/icons/owner/|assets/art/|\.claude/)'
mkdir -p "$DEST"
[ -d "$DEST/.git" ] || git -C "$DEST" init -q -b main
git -C "$DEST" config user.name SCP120
git -C "$DEST" config user.email 64856050+SCP120@users.noreply.github.com
LIST="$(mktemp)"
git -C "$ROOT" ls-files --cached --others --exclude-standard | grep -vE "$EXCLUDE" | while read -r f; do [ -f "$ROOT/$f" ] && echo "$f"; done > "$LIST"
# the tree is rebuilt each time, so a file left out here also leaves the public tree
find "$DEST" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
rsync -a --files-from="$LIST" "$ROOT/" "$DEST/"
echo "exported $(wc -l < "$LIST" | tr -d ' ') files to $DEST"
rm -f "$LIST"
