// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BuildContractTests {
    static func run(expect: (Bool, String) -> Void) {
        HarnessSourceTests.run(expect: expect)
        let buildScript = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""

        // MARK: Every temp dir build.sh stages in is swept when the script ends
        // `mktemp -d` lands outside the repo, so a dir the script does not
        // remove survives the run — a successful one as much as a failed one.
        // The sweep is therefore a trap, and a staging dir added later leaks on
        // every build until it is named in cleanup(). The names are read out of
        // the script so the two cannot drift apart.
        // The trap has to be installed before the first dir exists: a failure
        // between `mktemp -d` and a later `trap` leaks exactly as before.
        let sweepInstalled = buildScript.range(of: "trap cleanup EXIT")?.lowerBound
        let firstStaged = buildScript.range(of: "mktemp -d")?.lowerBound
        expect(sweepInstalled != nil && firstStaged != nil && sweepInstalled! < firstStaged!,
               "build.sh installs the temp dir sweep before it stages the first dir")
        // zsh runs the EXIT trap on HUP but not on INT or TERM, so the signals
        // have to reach it through `exit` or Ctrl-C leaks the staged bundle.
        let signalsRouted = buildScript.range(of: "trap 'exit 1' INT TERM HUP")?.lowerBound
        expect(signalsRouted != nil && firstStaged != nil && signalsRouted! < firstStaged!,
               "build.sh routes interrupts through the sweep before it stages the first dir")
        let cleanupBody = buildScript.components(separatedBy: "cleanup() {")
            .dropFirst().first?.components(separatedBy: "\n}").first ?? ""
        let stagedTempDirs = buildScript.components(separatedBy: "=\"$(mktemp -d)\"")
            .dropLast()
            .compactMap {
                $0.split(whereSeparator: { $0.isNewline || $0 == " " || $0 == "\t" })
                    .last.map(String.init)
            }
        expect(!stagedTempDirs.isEmpty, "the staged temp dirs read back out of build.sh")
        // A dir reached through a path suffix — `X="$(mktemp -d)/name"` — puts
        // the parent in no variable at all, which is how the bundle staging dir
        // leaked. Every call has to be captured whole to be sweepable.
        expect(buildScript.components(separatedBy: "mktemp -d").count - 1 == stagedTempDirs.count,
               "every mktemp -d in build.sh is a whole capture — no path suffix, no other spelling")
        for variable in Set(stagedTempDirs) {
            expect(cleanupBody.contains("\"$\(variable)\""),
                   "temp dir \(variable) is swept by build.sh cleanup()")
            // The sweep runs under `set -u` before the dir is staged: an entry
            // whose variable is not empty first aborts cleanup() at that line,
            // leaving everything listed below it unswept and the exit status
            // untouched. The empty assignment is the third line of the pattern.
            // The leading newline keeps ICON_TMP off STAGE_ICON_TMP.
            let initialized = buildScript.range(of: "\n\(variable)=\"\"")?.lowerBound
            expect(initialized != nil && sweepInstalled != nil && initialized! < sweepInstalled!,
                   "temp dir \(variable) is empty before the sweep is installed")
        }

        // MARK: An identity-less build that installs creates its stable signing identity
        // An ad-hoc signature changes hash on every build, so macOS orphans
        // Accessibility and Screen Recording grants on each rebuild while
        // System Settings keeps showing them as granted. build.sh therefore
        // routes identity-less installs through Tools/setup-signing.sh before
        // signing. The needle is the invocation at the start of a command
        // line: the ad-hoc fallback's advice string also names the script, and
        // must not satisfy this check.
        let runsSigningSetup = buildScript.components(separatedBy: "\n").contains {
            $0.range(of: #"^\s*(if\s+!?\s*)?\./Tools/setup-signing\.sh"#,
                     options: .regularExpression) != nil
        }
        expect(runsSigningSetup,
               "an identity-less build that installs invokes Tools/setup-signing.sh itself")
        // The guard is on the install, not on the variant: a plain --install
        // replaces the bundle under the released id, so it strands the grants
        // on the app people actually use. CI never passes --install.
        let buildScriptCode = buildScript.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        expect(buildScriptCode.contains { $0.contains("(( DEV || INSTALL ))")
                                            && $0.contains("developer_id_identity") },
               "the signing setup guard covers every install, not only the Developer variant")
        // The setup script must run against the stock /usr/bin/openssl, which
        // is LibreSSL: it rejects OpenSSL 3's -legacy flag outright, and the
        // script once died on exactly that with its stderr discarded. The
        // portable spelling names the PBE algorithms instead of the flag.
        let signingSetup = (try? String(contentsOfFile: "Tools/setup-signing.sh",
                                         encoding: .utf8)) ?? ""
        expect(!signingSetup.isEmpty, "the signing setup script reads back for its shape check")
        let signingSetupCode = signingSetup.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
        expect(!signingSetupCode.contains("-legacy"),
               "setup-signing.sh avoids the -legacy flag the stock LibreSSL openssl rejects")

        // MARK: The stable identity is judged by whether codesign can sign with it
        // A find-identity listing names certificates codesign then rejects, and
        // -v excludes every self-signed one, so neither spelling may decide.
        for (script, code, identity) in [("build.sh", buildScriptCode, "$LEGACY_IDENTITY"),
                                         ("Tools/setup-signing.sh", signingSetupCode.components(separatedBy: "\n"),
                                          "$IDENTITY")] {
            expect(!code.contains { $0.contains("find-identity") && $0.contains(identity) },
                   "\(script) never decides the stable identity by a find-identity listing")
            expect(code.contains { $0.contains("cp /bin/echo") }
                    && code.contains { $0.contains("--sign \"\(identity)\" \"$probe\"") },
                   "\(script) asks codesign to sign a throwaway copy of /bin/echo with the stable identity")
        }
    }
}
