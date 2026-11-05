#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
set -euo pipefail
cd "$(dirname "$0")/.."
task_temp="$(mktemp -d /private/tmp/tmobile-monitor-tests.XXXXXX)"
trap 'rm -rf "$task_temp"' EXIT
task_sdk="$(xcrun --show-sdk-path)"
# The string catalog switches over every production language case.
python3 - "$task_temp/AppLanguage.swift" <<'PY'
import re
import sys
source = open("Sources/Vorssaint/Core/Localization.swift").read()
cases = re.search(r"^enum AppLanguage: String, CaseIterable, Identifiable \{\n((?:    case .*\n)+)", source, re.M)
assert cases, "Expected the AppLanguage case list"
open(sys.argv[1], "w").write("enum AppLanguage: String, CaseIterable {\n" + cases.group(1) + "}\n")
PY
swiftc -Onone -sdk "$task_sdk" -module-cache-path "$task_temp/module-cache" \
    Sources/Vorssaint/Services/Metrics/TMobileGatewaySupport.swift \
    Sources/Vorssaint/Services/Metrics/TMobileGatewayConnectedRadioSupport.swift \
    Sources/Vorssaint/Services/Metrics/TMobileGatewayService.swift \
    Sources/Vorssaint/Services/Metrics/TMobileGatewayMenuBarSupport.swift \
    Sources/Vorssaint/Core/TMobileGatewayStrings.swift "$task_temp/AppLanguage.swift" \
    Sources/Vorssaint/Services/Metrics/TMobileGatewayMonitor.swift \
    Tests/Fixtures/TMobileGatewayMonitorHarness.swift -o "$task_temp/tests"
"$task_temp/tests"

# Compile the real grouping switch against every production metric case. This
# catches a new pin omitted from either grouping or click focus handling.
python3 - "$task_temp" <<'PY'
from pathlib import Path
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("test_generator", "Tests/generate_sources.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
cases = "\n".join(line for line in generator.declaration(
    "Sources/Vorssaint/App/MenuBarRenderer.swift", "enum MenuBarMetric:").splitlines()
    if line.startswith("    case "))
method = generator.declaration("Sources/Vorssaint/App/StatusItemController.swift",
                               "    static func metricStatusGroups(")
method = method.replace("UserDefaults.standard", "ReviewDefaults.current!")
fixture = Path("Tests/Fixtures/TMobileMenuBarGroupsHarness.swift").read_text()
fixture = fixture.replace("    // PRODUCTION_METRIC_CASES", cases)
fixture = fixture.replace("    // PRODUCTION_GROUPS_METHOD", method)
Path(sys.argv[1], "Groups.swift").write_text(fixture)
PY
swiftc -parse-as-library -Onone -sdk "$task_sdk" -module-cache-path "$task_temp/module-cache" \
    "$task_temp/Groups.swift" -o "$task_temp/groups-tests"
"$task_temp/groups-tests"
