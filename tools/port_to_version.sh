#!/bin/bash
# Port this Windows 7 qtbase overlay from one Qt version to another.
#
#   tools/port_to_version.sh <from-tag> <to-tag> [workdir]
#   tools/port_to_version.sh v6.11.1 v6.11.2
#
# Three-way merges every overlay file: ours = this repo's file, base = the
# pristine qtbase file at <from-tag>, theirs = the pristine file at <to-tag>.
# Files the overlay adds (restored from older Qt) are carried over untouched.
# Every side is normalised to LF before merging, because the overlay is stored
# with CRLF while qtbase is LF; without this every file conflicts spuriously.
# The merged result is written with LF, so a ported branch is LF throughout.
# Writes the result to <workdir>/out/qtbase and prints a per-file report;
# copy it over qtbase/ once the conflicts are resolved by hand.
set -u

FROM=${1:?usage: port_to_version.sh <from-tag> <to-tag> [workdir]}
TO=${2:?usage: port_to_version.sh <from-tag> <to-tag> [workdir]}
WORK=${3:-$(dirname "$0")/../.port}
REPO=$(cd "$(dirname "$0")/.." && pwd)

mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
for tag in "$FROM" "$TO"; do
    if [ ! -d "$WORK/qtbase-$tag" ]; then
        echo "cloning pristine qtbase $tag ..."
        git -c core.autocrlf=false clone --depth 1 --branch "$tag" --single-branch \
            https://github.com/qt/qtbase.git "$WORK/qtbase-$tag" || exit 1
    fi
done

OUT=$WORK/out/qtbase
TMP=$WORK/tmp
rm -rf "$OUT" "$TMP"; mkdir -p "$OUT" "$TMP"
conflicts=0

printf "%-62s %-10s %8s %8s\n" "FILE" "STATUS" "W7DELTA" "QTCHG"
cd "$REPO/qtbase" || exit 1
while read -r f; do
    ours="$TMP/ours"; base="$WORK/qtbase-$FROM/$f"; theirs="$WORK/qtbase-$TO/$f"
    tr -d '\r' < "$REPO/qtbase/$f" > "$ours"
    mkdir -p "$OUT/$(dirname "$f")"
    if [ ! -f "$base" ]; then                    # added by the overlay
        cp "$ours" "$OUT/$f"; st="NEW"; w7=$(wc -l < "$ours"); qt="-"
    elif [ ! -f "$theirs" ]; then                # dropped by the new Qt
        cp "$ours" "$OUT/$f"; st="GONE-IN-$TO"; w7="-"; qt="-"
    else
        w7=$(diff "$base" "$ours" | grep -c '^[<>]')
        qt=$(diff "$base" "$theirs" | grep -c '^[<>]')
        if [ "$w7" = "0" ]; then                 # overlay file has no Win7 delta
            cp "$theirs" "$OUT/$f"; st="NOOP"
        else
            git merge-file -p --diff3 "$ours" "$base" "$theirs" > "$OUT/$f" 2>/dev/null
            if [ $? -eq 0 ]; then st="CLEAN"; else st="CONFLICT"; conflicts=$((conflicts + 1)); fi
        fi
    fi
    printf "%-62s %-10s %8s %8s\n" "$f" "$st" "$w7" "$qt"
done < <(find . -type f | sed 's|^\./||' | sort)
rm -rf "$TMP"

echo
echo "result in $OUT ($conflicts file(s) with conflict markers)"
echo "after resolving, verify the tdesktop patches still apply:"
echo "  cp -r $OUT/src/. <pristine $TO>/src/ && git apply <patches>/qtbase_*/*.patch"
