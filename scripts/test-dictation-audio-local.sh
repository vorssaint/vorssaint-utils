#!/bin/zsh
# Local-only audio-fixture check. The fixture directory is intentionally ignored
# because recordings can contain private speech and must never reach Git.
set -euo pipefail

fixture="${1:-Audio de teste/WhatsApp Ptt 2026-08-30 at 18.49.40.ogg}"

if [[ ! -f "$fixture" ]]; then
  print "SKIP: áudio local não encontrado: $fixture"
  exit 0
fi

metadata="$(afinfo "$fixture")"
duration="$(print -r -- "$metadata" | awk '/estimated duration:/ { print $3; exit }')"
frames="$(print -r -- "$metadata" | awk '/valid frames/ { print $2; exit }')"

if [[ -z "$duration" ]] || ! awk "BEGIN { exit !($duration > 0.05) }"; then
  print -u2 "FAIL: o arquivo não possui duração reproduzível."
  exit 1
fi

if [[ -z "$frames" ]] || ! awk "BEGIN { exit !($frames > 0) }"; then
  print -u2 "FAIL: o arquivo não possui frames de áudio."
  exit 1
fi

print "OK: fixture local válido — ${duration}s, ${frames} frames."
