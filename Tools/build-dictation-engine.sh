#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
set -euo pipefail
cd "${0:A:h:h}"
readonly engine_revision=f1dcd15858c4bbba87ca97862b4e448b2cf15b8f
readonly engine_source="$PWD/.build/transcribe-cpp-source"
if [[ ! -d "$engine_source/.git" ]]; then
    git clone --depth 1 --branch v0.4.0 https://github.com/handy-computer/transcribe.cpp.git "$engine_source"
fi
if [[ "$(git -C "$engine_source" rev-parse HEAD)" != "$engine_revision" ]]; then
    print -u2 "Dictation engine source must be pinned to $engine_revision"
    exit 1
fi
command -v cmake >/dev/null || { print -u2 'CMake is required to build local dictation (brew install cmake).'; exit 1; }
cmake -S Sources/DictationWorker -B .build/dictation-engine \
    -DTRANSCRIBE_SOURCE="$engine_source" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DCMAKE_OSX_ARCHITECTURES=arm64 -DGGML_CCACHE=OFF
cmake --build .build/dictation-engine --target VorssaintDictationWorker --parallel "${VORSS_BUILD_JOBS:-4}"
mkdir -p build
cp .build/dictation-engine/VorssaintDictationWorker build/VorssaintDictationWorker
build/VorssaintDictationWorker --selftest
