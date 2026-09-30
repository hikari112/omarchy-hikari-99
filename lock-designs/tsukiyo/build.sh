#!/bin/bash
# Compile sky.frag and point Tsukiyo.qml at it. The shell caches shaders by
# path, so each build gets a name of its own and an edit shows up live.
set -euo pipefail
cd "$(dirname "$0")"
hash=$(sha1sum sky.frag | cut -c1-8)
out="sky-$hash.frag.qsb"
/usr/lib/qt6/bin/qsb --qt6 -o "$out" sky.frag
find . -maxdepth 1 -name 'sky*.frag.qsb' ! -name "$out" -delete
sed -i "s|fragmentShader: Qt.resolvedUrl(\"tsukiyo/[^\"]*\")|fragmentShader: Qt.resolvedUrl(\"tsukiyo/$out\")|" ../Tsukiyo.qml
echo "$out"

# Tsukiyo Real Sky is Tsukiyo with its clock on the real sun. It is generated
# here from Tsukiyo.qml, so the two never drift apart: edit Tsukiyo.qml only.
sed -e 's|^  property bool followSun: false$|  property bool followSun: true|' \
    -e '1s|.*|// Tsukiyo Real Sky 月夜. Generated from Tsukiyo.qml by tsukiyo/build.sh: edit that file, then run build.sh.|' \
    ../Tsukiyo.qml > ../TsukiyoRealSky.qml
grep -q '^  property bool followSun: true$' ../TsukiyoRealSky.qml || { echo "TsukiyoRealSky.qml: followSun not switched" >&2; exit 1; }
