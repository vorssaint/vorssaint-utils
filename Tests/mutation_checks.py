#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Verify that selected real regressions fail their existing tests.

Each mutation runs in a temporary copy and must fail an assertion with the
expected diagnostic. Compiler errors, timeouts and unrelated failures do not
count as detection. The working checkout and its build cache stay untouched.
"""
from pathlib import Path
import os
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

MUTATIONS = [
    ("invalid numeric result", "harness", "Tests/TestSuite.swift",
     "actual.isFinite && expected.isFinite && tol.isFinite && tol >= 0\n                   && abs(actual - expected) <= tol",
     "!(abs(actual - expected) > tol)", "every invalid numeric comparison fails"),
    ("invalid saved zoom", "core", "Sources/Vorssaint/Services/QuickTools/ScreenshotSupport.swift",
     "guard requested.isFinite else { return 1 }", "guard requested.isFinite else { return requested }",
     "an invalid saved magnifier zoom falls back safely"),
    ("missing recording action", "launcher", "Sources/Vorssaint/Services/QuickTools/QuickLauncherService.swift",
     "                ScreenRecorderService.shared.toggle()", "                // ScreenRecorderService.shared.toggle()",
     "screenRecorder executes the intended action exactly once"),
    ("incorrect recording icon", "launcher", "Sources/Vorssaint/UI/QuickLauncher/QuickLauncherView.swift",
     'case .screenRecorder: return recorder.isRecording ? "stop.circle" : "record.circle"',
     'case .screenRecorder: return "record.circle"', "an active recording tile offers stopping"),
    ("missing translation", "localization", "Sources/Vorssaint/Core/FeatureStrings.swift",
     'shortcutHint: "Clique numa linha para colar no app anterior. ⌘+clique seleciona várias; ⌘C copia sem colar."',
     'shortcutHint: ""', "clipboard/pt-BR: missing text in shortcutHint"),
    ("unsafe argument comparison", "harness", "Tests/LocalizationTests.swift",
     "actual?.arguments == expected?.arguments",
     "actual?.arguments.values.sorted() == expected?.arguments.values.sorted()",
     "localization validation detects missing text and unsafe argument swaps"),
    ("overwrite unreadable notes", "storage", "Sources/Vorssaint/Services/QuickTools/ScratchpadStore.swift",
     "        guard canSave else { return false }", "        // guard canSave else { return false }",
     "damaged scratchpad blocks subsequent saves of empty and nonempty documents"),
]


def run(directory, arguments):
    process = subprocess.Popen(["./build.sh", *arguments], cwd=directory,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=600)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        process.communicate()
        raise RuntimeError("Mutation run timed out; this is not a detected regression")
    return process.returncode, output


def main():
    with tempfile.TemporaryDirectory(prefix="vorss-mutation-") as temporary:
        directory = Path(temporary)
        # APFS clones keep the snapshot cheap and preserve timestamps so the
        # compiler can reuse unaffected objects after the baseline build.
        tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
        entries = sorted({path.split("/")[0] for path in tracked if path})
        for name in entries:
            subprocess.run(["/bin/cp", "-cRp", str(ROOT / name), str(directory / name)], check=True)
        for name in ["objects/tests", "generated-tests", "metrics-tests"]:
            source = ROOT / "build" / name
            if source.exists():
                target = directory / "build" / name
                target.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run(["/bin/cp", "-cRp", str(source), str(target)], check=True)

        print("Checking the unmodified baseline…", flush=True)
        status, output = run(directory, ["--test"])
        if status != 0 or "TESTS OK" not in output:
            raise RuntimeError("Baseline failed:\n" + output[-12000:])
        for name, group, relative, before, after, diagnostic in MUTATIONS:
            path = directory / relative
            original = path.read_text()
            if original.count(before) != 1:
                raise RuntimeError(f"Mutation fixture needs updating: {name}")
            print(f"Checking: {name}…", flush=True)
            try:
                path.write_text(original.replace(before, after))
                status, output = run(directory, ["--test-suite=" + group])
                if status != 1 or "TESTS FAILED" not in output or diagnostic not in output:
                    raise RuntimeError(f"Mutation was not caught by its intended assertion: {name}\n{output[-12000:]}")
                print(f"DETECTED: {name}", flush=True)
            finally:
                path.write_text(original)
        print(f"MUTATION CHECKS OK ({len(MUTATIONS)} regressions detected)", flush=True)


if __name__ == "__main__":
    main()
