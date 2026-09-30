#!/bin/bash
# Compile sky.frag and point Hikari-99.qml at it. The shell caches shaders by
# path, so each build gets a name of its own and an edit shows up live.
set -euo pipefail
cd "$(dirname "$0")"
hash=$(sha1sum sky.frag | cut -c1-8)
out="sky-$hash.frag.qsb"
/usr/lib/qt6/bin/qsb --qt6 -o "$out" sky.frag
find . -maxdepth 1 -name 'sky*.frag.qsb' ! -name "$out" -delete
sed -i "s|fragmentShader: Qt.resolvedUrl(\"hikari-99/[^\"]*\")|fragmentShader: Qt.resolvedUrl(\"hikari-99/$out\")|" ../Hikari-99.qml
echo "$out"


# Hikari 99 Real Sky is Hikari 99 with its clock on the real sun. It is
# generated here from Hikari-99.qml, so the two never drift apart: edit
# Hikari-99.qml only.
sed -e 's|^  property bool followSun: false$|  property bool followSun: true|' \
    -e '1s|.*|// Hikari 99 Real Sky 光. Generated from Hikari-99.qml by hikari-99/build.sh: edit that file, then run build.sh.|' \
    ../Hikari-99.qml > ../Hikari-99-Real-Sky.qml
grep -q '^  property bool followSun: true$' ../Hikari-99-Real-Sky.qml || { echo "Hikari-99-Real-Sky.qml: followSun not switched" >&2; exit 1; }
