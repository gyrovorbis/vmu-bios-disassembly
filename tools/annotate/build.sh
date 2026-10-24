#!/bin/bash
# Usage: tools/annotate/build.sh <american_v1.05.bin> [waterbear]
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
ROM=${1:?path to the original american_v1.05.bin}
WB=${2:-waterbear}
BASE=20b868d
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

git -C "$REPO" show $BASE:american_v1.05.s > "$W/base.s"
"$WB" disassemble -p -a -t bios "$ROM" -o "$W/dis.s" > /dev/null
python3 -I "$HERE/patch_rom.py" "$ROM" "$W/patched.bin"
"$WB" disassemble -p -a -t bios "$W/patched.bin" -o "$W/pdis.s" > /dev/null
python3 -I "$HERE/addrmap.py" "$W/base.s" "$W/dis.s" "$W/linemap.txt" 2> "$W/addrmap.log"
python3 -I "$HERE/apply.py" "$W/base.s" "$W/linemap.txt" "$W/pdis.s" "$HERE/annotations.txt" "$W/out.s"
python3 -I "$HERE/fixups.py" "$W/out.s"
"$WB" assemble "$W/out.s" -o "$W/out.bin" > /dev/null
if cmp -s "$W/out.bin" "$ROM"; then
    cp "$W/out.s" "$REPO/american_v1.05.s"
    echo "american_v1.05.s regenerated, assembles byte-identical to $ROM"
else
    echo "assembled output differs from $ROM; american_v1.05.s left untouched" >&2
    cmp -l "$W/out.bin" "$ROM" | head >&2
    exit 1
fi
