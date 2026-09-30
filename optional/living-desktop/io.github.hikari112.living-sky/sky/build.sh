#!/bin/bash
# Compile sky.frag and point Background.qml at it. The shell caches shaders by
# path, so each build gets a name of its own and an edit shows up live.
set -euo pipefail
cd "$(dirname "$0")"
hash=$(sha1sum sky.frag | cut -c1-8)
out="sky-$hash.frag.qsb"
/usr/lib/qt6/bin/qsb --qt6 -o "$out" sky.frag
find . -maxdepth 1 -name 'sky*.frag.qsb' ! -name "$out" -delete
sed -i "s|fragmentShader: Qt.resolvedUrl(\"sky/[^\"]*\")|fragmentShader: Qt.resolvedUrl(\"sky/$out\")|" ../Background.qml
echo "$out"
