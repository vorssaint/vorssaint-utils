#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
#
# Puts ffmpeg, ffprobe and 7-Zip inside the app so conversions work offline on
# any Mac. ffmpeg's libraries are copied beside it and re-pointed with
# dylibbundler, then everything is signed with the identity the app uses.
#
#   Tools/bundle-converters.sh <Vorssaint.app> [sign-identity]
#
# Sources: Homebrew's ffmpeg and sevenzip (brew install ffmpeg sevenzip
# dylibbundler), or FFMPEG_BIN_DIR / SEVENZIP_BIN pointing at your own builds.
# ffmpeg is GPL; see NOTICE for its licence and where its source is.
set -euo pipefail

APP="${1:?usage: bundle-converters.sh <Vorssaint.app> [identity]}"
IDENTITY="${2:--}"
BIN="$APP/Contents/Resources/bin"
LIBS="$APP/Contents/Frameworks/converters"
FFMPEG_DIR="${FFMPEG_BIN_DIR:-/opt/homebrew/bin}"
SEVENZIP="${SEVENZIP_BIN:-$FFMPEG_DIR/7zz}"

if [[ ! -x "$FFMPEG_DIR/ffmpeg" || ! -x "$FFMPEG_DIR/ffprobe" ]] || ! command -v dylibbundler >/dev/null; then
    echo "  converters not bundled: need ffmpeg, ffprobe and dylibbundler (brew install ffmpeg dylibbundler)" >&2
    exit 0
fi

rm -rf "$BIN" "$LIBS"
mkdir -p "$BIN" "$LIBS"
for tool in ffmpeg ffprobe; do
    cp "$FFMPEG_DIR/$tool" "$BIN/$tool"
    chmod u+w "$BIN/$tool"
    dylibbundler -od -b -x "$BIN/$tool" -d "$LIBS" -p "@executable_path/../../Frameworks/converters/" >/dev/null 2>&1
done
[[ -x "$SEVENZIP" ]] && cp "$SEVENZIP" "$BIN/7zz" && chmod u+w "$BIN/7zz"

# Every Mach-O gets signed on its own, libraries first, before the app's own signature.
for file in "$LIBS"/*.dylib(N) "$BIN"/*(N); do
    /usr/bin/codesign --force --strip-disallowed-xattrs --sign "$IDENTITY" "$file" >/dev/null 2>&1
done
echo "  converters bundled: $(du -sh "$BIN" "$LIBS" | awk '{print $1}' | paste -sd+ -) (bin+libs)"
