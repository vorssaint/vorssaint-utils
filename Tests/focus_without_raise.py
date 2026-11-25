#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Opt-in native reproduction of #3660. Use --preflight, --run, or --edge-cases on macOS.

Run from a trusted terminal in an unlocked desktop session. --run briefly
activates two disposable apps. Leave the keyboard, mouse and foreground alone.
The probe exercises the production no-raise handoff directly, independently of
hover detection. It observes AppKit key status, AX focus and stacking order.
It does not inject keystrokes, move the pointer, or read document contents.
--run checks same-app and cross-app transfers. --edge-cases checks refusal
within and between apps, explicit caller cancellation while selecting a third
window, and the order of a window that raises itself on mouse-down. The last
case checks stacking alone. Both modes run a positive control.
Exit 0 passed, 1 reproduced #3660 (accepted, app front, no target focus, order
preserved at both observations), 2 skipped/inconclusive, 3 edge-case failure.
"""
import argparse
from contextlib import ExitStack
from pathlib import Path
import plistlib
import runpy
import shutil
import signal
import subprocess
import sys
import tempfile

TESTS = Path(__file__).resolve().parent
ROOT = TESTS.parent
SERVICES = "Sources/Vorssaint/Services/"


def production_source():
    declaration = runpy.run_path(str(TESTS / "generate_sources.py"))["declaration"]
    bridge = SERVICES + "Switcher/SpaceWindowBridge.swift"
    activator = SERVICES + "Switcher/WindowActivator.swift"
    resolver = SERVICES + "Switcher/AXWindowResolver.swift"
    support = SERVICES + "FocusFollowsMouse/FocusFollowsMouseSupport.swift"

    def block(path, first, following):
        source = (ROOT / path).read_text()
        start = source.index(first)
        return source[start:source.index(following, start)]

    # Extract the same native bridge and AX reads as the app, including the
    # private symbol lookups. Changes to their dependencies must compile here.
    return (
        "import AppKit\nimport ApplicationServices\n"
        + block(resolver, "@_silgen_name", "enum AXWindowResolver")
        + "enum AXWindowResolver {\n"
        + declaration(resolver, "    static func windowID(for") + "}\n"
        + "enum WindowActivator {\n"
        + block(activator, "    private enum FocusedWindowOutcome", "    static func windowIsMinimized")
        + """
    static func observedFocus(for pid: pid_t) throws -> CGWindowID? {
        let reading = focusedWindowReading(for: pid)
        switch reading.outcome {
        case .focusedWindow, .noFocusedWindow: return reading.windowID
        case .readFailed where reading.axError == .noValue: return nil
        default: throw ProbeError("Could not read the disposable app's AX focused window.")
        }
    }
}
"""
        + "\nenum FocusFollowsMouseSupport {\n"
        + declaration(support, "    static func shouldRestoreFocus") + "}\n"
        + "enum SpaceWindowBridge {\n"
        + declaration(bridge, "    private static func symbol(")
        + block(bridge, "    private typealias SetFrontFunction", "    /// Asks the window server")
        + block(bridge, "    static func focusWithoutRaise(", "    // MARK: - The user's") + "}\n"
    )


def make_fixture(binary, directory, role):
    contents = directory / (role + ".app") / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    shutil.copy2(binary, contents / "MacOS/FocusFixture")
    info = {
        "CFBundleIdentifier": "org.local.vorss.focusprobe." + role.lower(),
        "CFBundleName": "Focus fixture " + role,
        "CFBundleExecutable": "FocusFixture",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
        "NSQuitAlwaysKeepsWindows": False,
        "NSPrincipalClass": "NSApplication",
    }
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--preflight", action="store_true", help="check session and permissions without opening windows")
    mode.add_argument("--run", action="store_true", help="run the control and both production handoffs")
    mode.add_argument("--edge-cases", action="store_true", help="check refusal, explicit cancellation and ordering")
    args = parser.parse_args()
    if sys.platform != "darwin":
        print("SKIP: requires macOS.")
        return 2
    with tempfile.TemporaryDirectory(prefix="vorssaint-focus-") as name:
        directory = Path(name)
        source = directory / "Production.swift"
        source.write_text(production_source())
        binary = directory / "FocusProbe"
        subprocess.run(["xcrun", "swiftc", "-swift-version", "5", str(source),
                        str(TESTS / "Fixtures/FocusWithoutRaise.swift"), "-o", str(binary)], check=True)
        if args.preflight:
            return subprocess.run([str(binary), "--preflight"]).returncode
        for role in ("A", "C"):
            make_fixture(binary, directory, role)
        with ExitStack() as stack:
            controller_mode = "--edge-cases" if args.edge_cases else "--controller"
            controller = subprocess.Popen([str(binary), controller_mode, name])

            def forward(signum, frame):
                if controller.poll() is None:
                    controller.send_signal(signum)

            for sig in (signal.SIGINT, signal.SIGHUP, signal.SIGTERM):
                previous = signal.signal(sig, forward)
                stack.callback(signal.signal, sig, previous)
            code = controller.wait()
            if code < 0:
                print(f"INCONCLUSIVE: controller terminated by signal {-code}.", file=sys.stderr)
                return 2
            return code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"INCONCLUSIVE: probe preparation failed: {error}", file=sys.stderr)
        sys.exit(2)
