#!/bin/bash
# Compile sky.frag and point Tsukiyo-99.qml at it. The shell caches shaders by
# path, so each build gets a name of its own and an edit shows up live.
set -euo pipefail
cd "$(dirname "$0")"
hash=$(sha1sum sky.frag | cut -c1-8)
out="sky-$hash.frag.qsb"
/usr/lib/qt6/bin/qsb --qt6 -o "$out" sky.frag
find . -maxdepth 1 -name 'sky*.frag.qsb' ! -name "$out" -delete
sed -i "s|fragmentShader: Qt.resolvedUrl(\"tsukiyo-99/[^\"]*\")|fragmentShader: Qt.resolvedUrl(\"tsukiyo-99/$out\")|" ../Tsukiyo-99.qml
echo "$out"

# Tsukiyo 99 Real Sky is Tsukiyo 99 with its clock on the real sun. It is
# generated here from Tsukiyo-99.qml, so the two never drift apart: edit
# Tsukiyo-99.qml only.
sed -e 's|^  property bool followSun: false$|  property bool followSun: true|' \
    -e '1s|.*|// Tsukiyo 99 Real Sky 月夜. Generated from Tsukiyo-99.qml by tsukiyo-99/build.sh: edit that file, then run build.sh.|' \
    ../Tsukiyo-99.qml > ../Tsukiyo-99-Real-Sky.qml
grep -q '^  property bool followSun: true$' ../Tsukiyo-99-Real-Sky.qml || { echo "Tsukiyo-99-Real-Sky.qml: followSun not switched" >&2; exit 1; }
