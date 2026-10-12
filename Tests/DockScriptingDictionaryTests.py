# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Compile client syntax against the shipping plist and scripting dictionary.

The fixture is never launched and cannot control windows or change preferences.
Its unique bundle ID avoids reading an installed app's cached terminology.
"""
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import uuid

resources = pathlib.Path(__file__).resolve().parent.parent / "Resources"
with tempfile.TemporaryDirectory(prefix="vorssaint-script-test-") as temporary:
    directory = pathlib.Path(temporary)
    bundle = directory / "Dictionary Test.app"
    contents = bundle / "Contents"
    (contents / "Resources").mkdir(parents=True)
    (contents / "MacOS").mkdir()
    info = plistlib.loads((resources / "Info.plist").read_bytes())
    info.update(CFBundleIdentifier="com.vorssaint.scripting-test." + str(uuid.uuid4()),
                CFBundleName="Dictionary Test", CFBundleExecutable="DictionaryTest")
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    definition = info["OSAScriptingDefinition"]
    shutil.copyfile(resources / definition, contents / "Resources" / definition)
    executable = contents / "MacOS" / "DictionaryTest"
    shutil.copyfile("/usr/bin/true", executable)
    executable.chmod(0o755)
    source = directory / "client.applescript"
    source.write_text(
        f'using terms from application "{bundle}"\n'
        f' tell application "{bundle}"\n'
        '  window command "windows"\n'
        '  window command "move" with parameters "{\\"id\\":42,\\"x\\":100,\\"y\\":100,\\"width\\":800,\\"height\\":600}"\n'
        ' end tell\nend using terms from\n', encoding="utf-8")
    subprocess.run(["/usr/bin/osacompile", "-o", str(directory / "client.scpt"), str(source)],
                   check=True, timeout=25)
print("DOCK SCRIPTING DICTIONARY TESTS OK (compile only; no app launched)")
