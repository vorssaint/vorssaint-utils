#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
"""Exercise the bundled worker with a real model and public speech fixture.

Usage: python3 Tests/dictation-engine-smoke.py MODEL_GGUF WAV_FILE
No microphone, clipboard, application preferences or personal history is read.
"""
import array
import json
import pathlib
import subprocess
import sys
import tempfile
import wave

root = pathlib.Path(__file__).resolve().parents[1]
model, sample = map(pathlib.Path, sys.argv[1:])
with wave.open(str(sample)) as source:
    assert source.getframerate() == 16000 and source.getnchannels() == 1 and source.getsampwidth() == 2
    audio = array.array("h", source.readframes(source.getnframes()))
    pcm = array.array("f", (value / 32768 for value in audio))
with tempfile.TemporaryDirectory(prefix="vorssaint-dictation-test-") as temporary:
    path = pathlib.Path(temporary) / "speech.f32"
    path.write_bytes(pcm.tobytes())
    worker = subprocess.Popen([str(root / "build/VorssaintDictationWorker")], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    request = json.dumps(dict(model=str(model.resolve()), audio=str(path), language="en", translate=False, vocabulary=[], cpu=False))
    try:
        # Two requests in the same worker also exercise warm-model reuse.
        output, _ = worker.communicate(request + "\n" + request + "\n", timeout=120)
        replies = [json.loads(line) for line in output.splitlines()]
        assert len(replies) == 2, output
        for reply in replies:
            assert "error" not in reply, reply
            assert "country" in reply["text"].lower(), reply
        print("PASS: two real local transcriptions through the Metal worker")
        print(replies[0]["text"])
    finally:
        if worker.poll() is None:
            worker.kill()
            worker.wait()
