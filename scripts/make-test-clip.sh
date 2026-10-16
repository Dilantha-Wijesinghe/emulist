#!/bin/zsh
# Builds a synthetic Apple Log ProRes 422 HQ clip from a photo (or the procedural chart).
# The photo is converted to scene-linear Rec.2020 and encoded with the Apple Log curve by emulist-cli;
# ffmpeg then does an independent Rec.2020 Y'CbCr encode, which also exercises our decoder.
#
#   scripts/make-test-clip.sh <photo.jpg|chart> <out.mov> [seconds]
set -euo pipefail
source="$1"; out="$2"; seconds="${3:-2}"
root="${0:A:h}/.."
cli="$root/.build/debug/emulist-cli"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [[ "$source" == chart ]]; then
  "$cli" chart "$tmp/log.tiff"
else
  "$cli" log-encode "$source" "$tmp/log.tiff"
fi

ffmpeg -loglevel error -y -loop 1 -framerate 24 -i "$tmp/log.tiff" -t "$seconds" \
  -vf "scale=out_color_matrix=bt2020:out_range=tv,format=yuv422p10le" \
  -c:v prores_ks -profile:v 3 -colorspace bt2020nc -color_primaries bt2020 -color_range tv "$out"
echo "wrote $out"
