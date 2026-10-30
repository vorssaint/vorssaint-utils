#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
set -euo pipefail
cd "$(dirname "$0")/.."
task_temp="$(mktemp -d /private/tmp/tmobile-appearance-tests.XXXXXX)"
trap 'rm -rf "$task_temp"' EXIT
task_sdk="$(xcrun --show-sdk-path)"

# Compile real presentation and drawing code with an in-memory preferences
# boundary. No app launch, standard preferences, network or Keychain access.
python3 - "$task_temp" <<'PY'
from pathlib import Path
import importlib.util
import re
import sys

spec = importlib.util.spec_from_file_location("generator", "Tests/generate_sources.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
folder = Path(sys.argv[1])
support = Path("Sources/Vorssaint/Services/Metrics/TMobileGatewayMenuBarSupport.swift").read_text()
assert support.count("UserDefaults.standard") == 1
support = support.replace("UserDefaults.standard", "FixturePreferences.defaults")
folder.joinpath("MenuBarSupport.swift").write_text(support)
defaults = Path("Sources/Vorssaint/Core/Defaults.swift").read_text()
keys = sorted(set(re.findall(r"DefaultsKey\.(\w+)", support)))
declarations = "\n".join(re.search(r"^    static let " + key + r" = .*", defaults, re.M).group(0)
                         for key in keys)
components_key = re.search(r'    static let tMobileMenuBarComponents = "([^"]+)"', defaults).group(1)
default_value = re.search(r"DefaultsKey.tMobileMenuBarComponents: (\d+)", defaults).group(1)
assert components_key == "tMobileMenuBarComponents" and default_value == "7"
style = generator.declaration("Sources/Vorssaint/App/MenuBarRenderer.swift", "enum MenuBarBlockStyle {")
toggle = generator.declaration("Sources/Vorssaint/UI/Settings/MonitorSettings.swift",
                               "    private func gatewayComponentToggle(")
folder.joinpath("Boundaries.swift").write_text("import SwiftUI\n"
    + "enum DefaultsKey {\n" + declarations + "\n}\n" + style
    + '\nfinal class FixtureValueBox { var components = 7 }\n'
    + 'struct FixtureToggle: View {\nlet box = FixtureValueBox()\n'
    + 'var gatewayComponents: Int { get { box.components } nonmutating set { box.components = newValue } }\n'
    + 'var gatewayStrings: TMobileGatewayStrings { .localized(.enUS) }\n'
    + 'var body: some View { gatewayComponentToggle("Technology", component: .technology) }\n'
    + toggle + "\n}\n")
PY

# The string catalog switches over every production language case.
python3 - "$task_temp/AppLanguage.swift" <<'PY'
import re
import sys
source = open("Sources/Vorssaint/Core/Localization.swift").read()
cases = re.search(r"^enum AppLanguage: String, CaseIterable, Identifiable \{\n((?:    case .*\n)+)", source, re.M)
assert cases, "Expected the AppLanguage case list"
open(sys.argv[1], "w").write("enum AppLanguage: String, CaseIterable {\n" + cases.group(1) + "}\n")
PY

xcrun swiftc -j1 -disable-batch-mode -parse-as-library -Onone -sdk "$task_sdk" \
    -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$task_temp/module-cache" \
    Sources/Vorssaint/Services/Metrics/TMobileGatewaySupport.swift \
    Sources/Vorssaint/Services/Metrics/TMobileGatewayConnectedRadioSupport.swift \
    "$task_temp/MenuBarSupport.swift" "$task_temp/Boundaries.swift" \
    Sources/Vorssaint/Core/TMobileGatewayStrings.swift "$task_temp/AppLanguage.swift" \
    Sources/Vorssaint/App/TMobileGatewayIndicatorDrawing.swift \
    Tests/Fixtures/TMobileGatewayAppearanceHarness.swift -o "$task_temp/tests"
"$task_temp/tests"
