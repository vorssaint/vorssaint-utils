#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Small live contract check for upstream yt-dlp/site changes. This is run only
# by the scheduled workflow, never by release tags or the offline test suite.
set -euo pipefail

for tool in yt-dlp ffmpeg ffprobe deno jq; do
    command -v "$tool" >/dev/null || { echo "Missing smoke-test tool: $tool" >&2; exit 1; }
done

WORK="$(mktemp -d /tmp/vorssaint-downloader-smoke.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

YOUTUBE_URL="https://www.youtube.com/watch?v=UyU-EGDbh2o"
DIRECT_URL="https://test-videos.co.uk/vids/bigbuckbunny/mkv/360/Big_Buck_Bunny_360_10s_1MB.mkv"
DENO_PATH="$(command -v deno)"
FFMPEG_PATH="$(command -v ffmpeg)"
# Keep the scheduled smoke aligned with the app's deterministic yt-dlp policy:
# the cache is confined to this run's work directory and EJS challenge solving
# is enabled, matching the app-owned cache the real app uses.
SECURITY_ARGS=(
    --ignore-config --no-config-locations --no-plugin-dirs --no-color
    --no-cookies --no-cookies-from-browser --no-exec --force-ipv4
    --cache-dir "$WORK/cache" --remote-components ejs:github
)

echo "▸ Inspecting the yt-dlp YouTube fixture"
printf '%s\n' "$YOUTUBE_URL" | yt-dlp "${SECURITY_ARGS[@]}" \
    --yes-playlist --playlist-items 1 --skip-download --dump-single-json \
    --no-check-formats \
    --socket-timeout 8 --batch-file - --js-runtimes "deno:$DENO_PATH" \
    > "$WORK/inspection.json"
jq -e '.id == "UyU-EGDbh2o" and .is_live == false
       and .automatic_captions["tr-orig"] != null' "$WORK/inspection.json" >/dev/null

echo "▸ Downloading the original-language automatic caption"
mkdir "$WORK/subtitles"
printf '%s\n' "$YOUTUBE_URL" | yt-dlp "${SECURITY_ARGS[@]}" \
    --no-playlist --playlist-items 1 --skip-download \
    --no-write-subs --write-auto-subs --sub-langs tr-orig \
    --sub-format srt/vtt/best --convert-subs srt \
    --paths "$WORK/subtitles" --output '%(id)s.%(ext)s' --batch-file - \
    --js-runtimes "deno:$DENO_PATH"
SUBTITLE="$(find "$WORK/subtitles" -maxdepth 1 -type f -name '*.tr-orig.srt' -size +0 -print -quit)"
[[ -n "$SUBTITLE" ]] || { echo "Original-language subtitle was not downloaded" >&2; exit 1; }

echo "▸ Exercising the MP4-first/MKV-fallback media selector"
mkdir "$WORK/video"
printf '%s\n' "$DIRECT_URL" | yt-dlp "${SECURITY_ARGS[@]}" \
    --no-playlist --playlist-items 1 --ffmpeg-location "$FFMPEG_PATH" \
    --no-overwrites --no-post-overwrites --no-keep-video \
    --paths "$WORK/video" --output '%(id)s.%(ext)s' \
    --format 'bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b' \
    --merge-output-format mp4/mkv --remux-video 'mp4>mp4/mov>mp4/mkv' \
    --batch-file - --js-runtimes "deno:$DENO_PATH"
MEDIA="$(find "$WORK/video" -maxdepth 1 -type f \( -name '*.mp4' -o -name '*.mkv' \) -size +0 -print -quit)"
[[ -n "$MEDIA" ]] || { echo "Fallback media was not downloaded" >&2; exit 1; }
ffprobe -v error -show_streams -show_format -of json "$MEDIA" > "$WORK/media.json"
jq -e 'any(.streams[]; .codec_type == "video")
       and (.format.format_name | test("(^|,)(mp4|matroska)(,|$)"))' \
    "$WORK/media.json" >/dev/null

echo "LIVE DOWNLOADER SMOKE OK"
