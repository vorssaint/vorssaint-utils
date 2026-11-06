// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A Keychain in memory, for the live Claude login and the saved copies.
final class AgentAccountTestSecrets: ClaudeSecretStore {
    private(set) var items: [String: String] = [:]
    private(set) var writes = 0
    /// Runs after each read, as Claude Code can change the item meanwhile.
    var afterRead: (() -> Void)?

    subscript(service: String, account: String) -> String? {
        get { items["\(service)|\(account)"] }
        set { items["\(service)|\(account)"] = newValue }
    }

    func read(service: String, account: String) throws -> String? {
        defer { afterRead?() }
        return self[service, account]
    }

    func write(_ value: String, service: String, account: String) throws {
        writes += 1
        self[service, account] = value
    }

    func delete(service: String, account: String) throws {
        self[service, account] = nil
    }
}

/// Saved logins in folders of their own: the store, a swap of each
/// provider's login, and the `security` tool behind the Keychain.
enum AgentAccountTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let user = "tester"

    static func run(_ suite: TestSuite) {
        keychain(suite)
        configSurgery(suite)
        store(suite)
        claudeSwitch(suite)
        claudeSwitchFailures(suite)
        codexIdentity(suite)
        codexSwitch(suite)
        AgentAccountLoginTests.run(suite)
        AgentAccountUsageTests.run(suite)
        AgentAccountAutoSwapTests.run(suite)
    }

    // MARK: Fixtures

    static func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
        return (try? Data(contentsOf: url)) ?? Data()
    }

    static func temporaryFolder(_ name: String) -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-accounts-\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func json(_ data: Data?) -> [String: Any] {
        data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
    }

    static func data(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    /// Whether a read found nothing, which `try?` cannot tell from a failure.
    static func isNone<T>(_ read: () throws -> T?) -> Bool {
        do { return try read() == nil } catch { return false }
    }

    static func fails<T>(_ body: () throws -> T) -> Bool {
        do { _ = try body(); return false } catch { return true }
    }

    static func mode(_ url: URL) -> Int? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue
    }

    /// A Claude Code credential for the login `name`, with whatever other
    /// top-level keys a test wants beside the tokens.
    static func claudeCredential(_ name: String, expires: Date = now.addingTimeInterval(8 * 3_600),
                                 extra: [String: Any] = [:]) -> Data {
        var root = extra
        root["claudeAiOauth"] = ["accessToken": "at-\(name)", "refreshToken": "rt-\(name)",
                                 "expiresAt": Int64(expires.timeIntervalSince1970 * 1_000),
                                 "scopes": ["user:inference", "user:profile"], "subscriptionType": "max"]
        return data(root)
    }

    static func claudeIdentity(_ name: String) -> String {
        #"{"accountUuid":"acct-\#(name)","emailAddress":"\#(name)@example.com","organizationUuid":"org-\#(name)","organizationName":"Org \#(name)"}"#
    }

    static func access(_ credential: String?) -> String? {
        (json(credential.map { Data($0.utf8) })["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String
    }

    /// A home folder Claude Code is signed in to, with the store and the
    /// adapter a swap goes through.
    final class ClaudeWorld {
        let home = AgentAccountTests.temporaryFolder("claude")
        let secrets = AgentAccountTestSecrets()
        let store: AgentAccountStore
        var adapter: ClaudeLoginAdapter

        init() {
            try? FileManager.default.createDirectory(at: home.appending(path: ".claude"), withIntermediateDirectories: true)
            store = AgentAccountStore(directory: home.appending(path: "store"),
                                      copies: [.claude: ClaudeCredentialCopies(secrets: secrets)])
            adapter = ClaudeLoginAdapter(home: home, secrets: secrets, account: AgentAccountTests.user)
            adapter.lockTimeout = 0.3
            adapter.now = { AgentAccountTests.now }
        }

        deinit { try? FileManager.default.removeItem(at: home) }

        var configURL: URL { home.appending(path: ".claude.json") }
        var config: String { (try? String(contentsOf: configURL, encoding: .utf8)) ?? "" }
        var live: String? {
            get { secrets[ClaudeCodeLogin.service, AgentAccountTests.user] }
            set { secrets[ClaudeCodeLogin.service, AgentAccountTests.user] = newValue }
        }
        func copy(_ name: String) -> String? { secrets[ClaudeCredentialCopies.service, "acct-\(name)/org-\(name)"] }
        var switcher: AgentAccountSwitcher { AgentAccountSwitcher(store: store, adapters: [.claude: adapter]) }

        /// What `claude auth login` leaves behind: the item and the identity.
        func signIn(_ name: String, credential: Data? = nil) {
            live = String(decoding: credential ?? AgentAccountTests.claudeCredential(name), as: UTF8.self)
            let text = #"{"numStartups":7,"oauthAccount":\#(AgentAccountTests.claudeIdentity(name)),"userID":"0f3a"}"#
            try? Data(text.utf8).write(to: configURL)
        }

        @discardableResult
        func save() -> AgentAccount? {
            (try? adapter.readLive()).flatMap { try? store.capture($0, now: AgentAccountTests.now) }
        }
    }

    // MARK: Keychain

    /// Plays `security` with one item kept beside the script, and notes how
    /// the last value came in: as a line on stdin or among the arguments.
    private static let securityStandIn = #"""
        #!/bin/sh
        dir="$(dirname "$0")"
        case "$1" in
          find-generic-password) [ -f "$dir/item" ] || exit 44; cat "$dir/item"; echo ;;
          delete-generic-password) [ -f "$dir/item" ] || exit 44; rm "$dir/item" ;;
          -i) IFS= read -r line; printf '%s' "$line" > "$dir/how"; printf '%s' "${line##*-X }" | xxd -r -p > "$dir/item" ;;
          add-generic-password) printf 'arguments' > "$dir/how"; for last; do :; done; printf '%s' "$last" | xxd -r -p > "$dir/item" ;;
          *) exit 2 ;;
        esac
        """#

    private static func keychain(_ suite: TestSuite) {
        let folder = temporaryFolder("security")
        defer { try? FileManager.default.removeItem(at: folder) }
        let tool = folder.appending(path: "security")
        guard FileManager.default.createFile(atPath: tool.path, contents: Data(securityStandIn.utf8),
                                             attributes: [.posixPermissions: 0o755]) else {
            suite.expect(false, "the stand-in security tool is written")
            return
        }
        let keychain = ClaudeKeychain(tool: tool.path)
        let how = { (try? String(contentsOf: folder.appending(path: "how"), encoding: .utf8)) ?? "" }

        suite.expect(isNone { try keychain.read(service: "Some Service", account: "me") },
                     "an item that is not there reads as none, not as a failure")
        let value = #"{"claudeAiOauth":{"accessToken":"sk-ant-é"}}"# + "\n"
        let stored: Void? = try? keychain.write(value, service: "Some Service", account: "me")
        let hex = Data(value.utf8).map { String(format: "%02x", $0) }.joined()
        suite.expect(stored != nil && how() == #"add-generic-password -U -a "me" -s "Some Service" -X \#(hex)"#,
                     "a value goes in as hex on the tool's stdin, never among its arguments")
        suite.expect((try? keychain.read(service: "Some Service", account: "me")) == value,
                     "only the newline the tool adds is taken off what it prints")

        let long = String(repeating: "x", count: 3_000)
        let storedLong: Void? = try? keychain.write(long, service: "Some Service", account: "me")
        suite.expect(storedLong != nil && how() == "arguments" && (try? keychain.read(service: "Some Service", account: "me")) == long,
                     "a value too long for one line of stdin still gets stored")

        let deleted: Void? = try? keychain.delete(service: "Some Service", account: "me")
        let again: Void? = try? keychain.delete(service: "Some Service", account: "me")
        suite.expect(deleted != nil && again != nil && isNone { try keychain.read(service: "Some Service", account: "me") },
                     "deleting removes the item, and deleting what is gone succeeds")

        suite.expect(ClaudeKeychain.decoded("7b2261223a22c3a9227d") == #"{"a":"é"}"#
                        && ClaudeKeychain.decoded(#"{"a":1}"#) == #"{"a":1}"#,
                     "a value the tool prints as hex reads as its text, and JSON is left as it is")
        suite.expect(fails { try ClaudeKeychain(tool: folder.appending(path: "missing").path).read(service: "s", account: "a") },
                     "a tool that cannot run is a failure, not a missing item")
    }

    // MARK: Config file

    private static func configSurgery(_ suite: TestSuite) {
        let config = fixture("agent-accounts-claude-config.json")
        let text = String(decoding: config, as: UTF8.self)
        let identity = ClaudeCodeLogin.liveIdentity(in: config)
        let who = identity.flatMap(ClaudeCodeLogin.identity)
        suite.expect(who == ClaudeCodeLogin.Identity(id: "acct-a/org-a", email: "a@example.com", organization: "A’s Organization"),
                     "the login is the top-level oauthAccount, not one nested in a project or quoted in a string")

        let next = Data(claudeIdentity("b").utf8)
        let replaced = ClaudeCodeLogin.replacingIdentity(in: config, with: next)
        let expected = identity.map { text.replacingOccurrences(of: String(decoding: $0, as: UTF8.self), with: claudeIdentity("b")) }
        suite.expect(replaced.map { String(decoding: $0, as: UTF8.self) } == expected && expected != text
                        && expected?.contains(#""lastCost": 0.1,"#) == true,
                     "a swap replaces the oauthAccount and leaves every other byte of the file as it was")

        let without = Data(#"{"numStartups":1,"projects":{"/p":{"oauthAccount":{"accountUuid":"x"}}}}"#.utf8)
        let added = ClaudeCodeLogin.replacingIdentity(in: without, with: next)
        suite.expect(added.flatMap(ClaudeCodeLogin.liveIdentity) == next && json(added)["numStartups"] as? Int == 1
                        && ClaudeCodeLogin.replacingIdentity(in: Data("{ }".utf8), with: next)
                            .flatMap(ClaudeCodeLogin.liveIdentity) == next,
                     "a file without an oauthAccount gets one, also when it is empty")
        suite.expect(ClaudeCodeLogin.replacingIdentity(in: Data("[1]".utf8), with: next) == nil
                        && ClaudeCodeLogin.replacingIdentity(in: Data(#"{"a":"#.utf8), with: next) == nil
                        && ClaudeCodeLogin.replacingIdentity(in: config, with: Data("nope".utf8)) == nil,
                     "a file or an identity that is not a JSON object is refused")
    }

    // MARK: Store

    private static func store(_ suite: TestSuite) {
        let folder = temporaryFolder("store")
        defer { try? FileManager.default.removeItem(at: folder) }
        let secrets = AgentAccountTestSecrets()
        let codexCopies = CodexCredentialCopies(directory: folder.appending(path: "codex"))
        func open() -> AgentAccountStore {
            AgentAccountStore(directory: folder, copies: [.claude: ClaudeCredentialCopies(secrets: secrets), .codex: codexCopies])
        }
        let store = open()
        let claude = AgentLiveLogin(id: "acct-a/org-a", provider: .claude, email: "a@example.com", organization: "Org a",
                                    identity: Data(claudeIdentity("a").utf8), credential: claudeCredential("a"))
        let auth = codexAuth(account: "c0de-1", email: "c@example.com")
        let codex = AgentLiveLogin(id: "c0de-1", provider: .codex, email: "c@example.com", organization: "pro",
                                   identity: Data(), credential: auth)
        let saved = try? store.capture(claude, now: now)
        _ = try? store.capture(codex, now: now.addingTimeInterval(1))
        try? store.rename("acct-a/org-a", label: "  Work \n")
        try? store.setNeedsLogin("acct-a/org-a", true)

        let file = folder.appending(path: AgentAccountStore.fileName)
        let authFile = folder.appending(path: "codex/c0de-1/auth.json")
        suite.expect(saved?.added == now && open().accounts == store.accounts && store.accounts.map(\.id) == ["acct-a/org-a", "c0de-1"]
                        && store.account("acct-a/org-a")?.label == "Work" && mode(file) == 0o600 && mode(folder) == 0o700,
                     "saved logins read back from an owner-only file as they were written")
        suite.expect(secrets[ClaudeCredentialCopies.service, "acct-a/org-a"] == String(decoding: claudeCredential("a"), as: UTF8.self)
                        && (try? Data(contentsOf: authFile)) == auth && mode(authFile) == 0o600
                        && mode(authFile.deletingLastPathComponent()) == 0o700
                        && (try? store.credential(for: "c0de-1")) == auth,
                     "a Claude copy goes to the Keychain under the login's id, a Codex copy to an owner-only folder of its own")

        let again = try? store.capture(AgentLiveLogin(id: "acct-a/org-a", provider: .claude, email: "new@example.com",
                                                      organization: "Org a", identity: Data(claudeIdentity("a").utf8),
                                                      credential: claudeCredential("a2")), now: now.addingTimeInterval(60))
        suite.expect(again?.added == now && again?.savedAt == now.addingTimeInterval(60) && again?.label == "Work"
                        && again?.needsLogin == false && again?.email == "new@example.com" && store.accounts.count == 2
                        && access(secrets[ClaudeCredentialCopies.service, "acct-a/org-a"]) == "at-a2",
                     "capturing a saved login again updates its copy and clears the need to log in, and keeps its label")

        try? store.remove("c0de-1")
        try? store.remove("acct-a/org-a")
        suite.expect(store.accounts.isEmpty && open().accounts.isEmpty && secrets.items.isEmpty
                        && !FileManager.default.fileExists(atPath: authFile.deletingLastPathComponent().path),
                     "removing a login deletes its copy with it")
        suite.expect(codexCopies.home(for: "../elsewhere") == nil && codexCopies.home(for: "..") == nil
                        && (try? codexCopies.write(auth, for: "a/b")) == nil,
                     "an id that could name a folder elsewhere is never used as one")

        let newer = Data(#"{"version":2,"accounts":[{"id":"x","from":"the future"}]}"#.utf8)
        try? newer.write(to: file)
        let reopened = open()
        suite.expect(reopened.accounts.isEmpty && (try? Data(contentsOf: file)) == newer,
                     "a file from a newer version reads as no logins and is left untouched")
    }

    // MARK: Claude swap

    private static func claudeSwitch(_ suite: TestSuite) {
        let world = ClaudeWorld()
        // A is saved with secrets of this Mac that have since changed.
        world.signIn("a", credential: claudeCredential("a", extra: ["mcpOAuth": ["server": "old"], "pluginSecrets": ["p": 1],
                                                                 "trustedDeviceToken": "device-a"]))
        world.save()
        world.signIn("b", credential: claudeCredential("b", extra: ["mcpOAuth": ["server": "old"]]))
        world.save()
        // Claude Code has rotated B's tokens and signed in to an MCP server since.
        world.live = String(decoding: claudeCredential("b2", extra: ["mcpOAuth": ["server": "now"], "mcpXaaIdp": ["idp": true]]),
                            as: UTF8.self)
        let fixtureText = String(decoding: fixture("agent-accounts-claude-config.json"), as: UTF8.self)
        try? Data(fixtureText.replacingOccurrences(of: "acct-a", with: "acct-b").replacingOccurrences(of: "org-a", with: "org-b").utf8)
            .write(to: world.configURL)
        let before = world.config

        suite.expect((try? world.adapter.readLive())?.id == "acct-b/org-b" && world.switcher.switch(to: "acct-b/org-b") == .success(.alreadyActive)
                        && world.secrets.writes == 2,
                     "swapping to the login already in use writes nothing")
        let result = world.switcher.switch(to: "acct-a/org-a")
        let live = json(world.live.map { Data($0.utf8) })
        suite.expect(result == .success(.switched) && access(world.live) == "at-a" && live["trustedDeviceToken"] as? String == "device-a",
                     "the saved login's tokens and its own keys become the live credential")
        suite.expect((live["mcpOAuth"] as? [String: String]) == ["server": "now"] && live["mcpXaaIdp"] != nil
                        && live["pluginSecrets"] == nil,
                     "this Mac's keys keep their live values, and one the live credential lacks is removed")
        suite.expect(access(world.copy("b")) == "at-b2",
                     "the login swapped away from is captured again first, with the tokens it had rotated to")

        let liveIdentity = (try? Data(contentsOf: world.configURL)).flatMap(ClaudeCodeLogin.liveIdentity)
        let expected = ClaudeCodeLogin.liveIdentity(in: Data(before.utf8)).map {
            before.replacingOccurrences(of: String(decoding: $0, as: UTF8.self), with: claudeIdentity("a"))
        }
        suite.expect(liveIdentity == Data(claudeIdentity("a").utf8) && world.config == expected && mode(world.configURL) == 0o600,
                     "the config file gets the saved identity and keeps every other key, owner-only")
        let credentialsFile = ClaudeCodeLogin.credentialsFileURL(home: world.home)
        suite.expect(!FileManager.default.fileExists(atPath: credentialsFile.path)
                        && (try? FileManager.default.contentsOfDirectory(atPath: world.home.path).sorted()) == [".claude", ".claude.json", "store"],
                     "the credentials file is never created, and no lock or temporary file is left behind")

        try? Data("{}".utf8).write(to: credentialsFile)
        let back = world.switcher.switch(to: "acct-b/org-b")
        suite.expect(back == .success(.switched) && access(world.live) == "at-b2"
                        && (try? String(contentsOf: credentialsFile, encoding: .utf8)) == world.live && mode(credentialsFile) == 0o600
                        && (try? world.adapter.readLive())?.id == "acct-b/org-b",
                     "a credentials file Claude Code keeps is rewritten with the swap, so running sessions load it")
    }

    private static func claudeSwitchFailures(_ suite: TestSuite) {
        let world = ClaudeWorld()
        world.signIn("a")
        world.save()
        world.signIn("b")
        world.save()
        let live = world.live, config = world.config, copies = world.secrets.items
        func untouched() -> Bool { world.live == live && world.config == config && world.secrets.items == copies }

        suite.expect(world.switcher.switch(to: "nobody") == .failure(.targetMissing) && untouched(), "a login that is not saved cannot be swapped to")
        try? world.store.setNeedsLogin("acct-a/org-a", true)
        suite.expect(world.switcher.switch(to: "acct-a/org-a") == .failure(.needsLogin) && untouched(),
                     "a saved login that is dead is not made the live one")
        try? world.store.setNeedsLogin("acct-a/org-a", false)

        // The lock on the config file, held by a Claude Code that is writing it.
        let held = world.home.appending(path: ".claude.json.lock")
        try? FileManager.default.createDirectory(at: held, withIntermediateDirectories: false)
        suite.expect(world.switcher.switch(to: "acct-a/org-a") == .failure(.busy) && untouched()
                        && FileManager.default.fileExists(atPath: held.path)
                        && !FileManager.default.fileExists(atPath: ClaudeLocks.refresh(home: world.home).url.path)
                        && !FileManager.default.fileExists(atPath: world.home.appending(path: ".claude.lock").path),
                     "a lock Claude Code holds stops the swap, and the locks taken before it are given back")
        // Left behind by a process that died: nobody touched it for a while.
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30)], ofItemAtPath: held.path)
        suite.expect(world.switcher.switch(to: "acct-a/org-a") == .success(.switched) && !FileManager.default.fileExists(atPath: held.path),
                     "a lock nobody touched past its time is taken over, and released after the swap")
        suite.expect(world.switcher.switch(to: "acct-b/org-b") == .success(.switched), "the way back works the same")

        let writesBefore = world.secrets.writes
        world.adapter.write = { data, url in
            if url.lastPathComponent == ".claude.json" { throw AgentLoginError.unreadable("disk full") }
            try AgentLoginFiles.write(data, to: url)
        }
        let liveNow = world.live, configNow = world.config
        let failed = world.switcher.switch(to: "acct-a/org-a")
        suite.expect(failed == .failure(.copyUnavailable("disk full")) && world.secrets.writes > writesBefore
                        && world.live == liveNow && world.config == configNow,
                     "when the identity cannot be written, the Keychain value already written is put back")
        world.adapter.write = AgentLoginFiles.write

        try? Data("not json".utf8).write(to: world.configURL)
        let writes = world.secrets.writes
        let unparseable = world.switcher.switch(to: "acct-a/org-a")
        suite.expect(isNone { try world.adapter.readLive() } && unparseable == .failure(.copyUnavailable(".claude.json is not a JSON object"))
                        && world.secrets.writes == writes,
                     "a config file that cannot be read stops the swap before anything is written")
        world.signIn("b")

        // Signed out: the item is left without tokens, as after `claude auth logout`.
        world.live = #"{"claudeAiOauth":{"accessToken":"","refreshToken":""},"mcpOAuth":{"kept":true}}"#
        suite.expect(world.switcher.switch(to: "acct-a/org-a") == .success(.switched) && access(world.live) == "at-a"
                        && (json(world.live.map { Data($0.utf8) })["mcpOAuth"] as? [String: Bool]) == ["kept": true]
                        && access(world.copy("b")) == "at-b",
                     "a signed-out Claude Code is signed in by the swap, and nothing empty replaces a copy")
        world.live = nil
        try? Data(#"{"numStartups":7}"#.utf8).write(to: world.configURL)
        suite.expect(world.switcher.switch(to: "acct-b/org-b") == .success(.switched) && access(world.live) == "at-b"
                        && (try? world.adapter.readLive())?.id == "acct-b/org-b" && world.config.contains(#""numStartups":7"#),
                     "without an item or an identity the swap writes both and keeps the rest of the config")
    }

    // MARK: Codex

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// An `auth.json` as Codex writes it for a plan's login.
    static func codexAuth(account: String, email: String, plan: String = "pro", refresh: String = "rt-1") -> Data {
        // The question marks and tildes make the encoding use its URL letters.
        let claims: [String: Any] = ["email": email, "name": "Tester ???~~~>>>",
                                     "https://api.openai.com/auth": ["chatgpt_account_id": account, "chatgpt_user_id": "user-1",
                                                                     "chatgpt_plan_type": plan]]
        let token = [data(["alg": "RS256"]), data(claims), Data("signature".utf8)].map(base64URL).joined(separator: ".")
        return data(["auth_mode": "chatgpt", "OPENAI_API_KEY": NSNull(), "last_refresh": "2026-10-12T08:00:00Z",
                     "tokens": ["id_token": token, "access_token": "at", "refresh_token": refresh, "account_id": account]])
    }

    private static func codexIdentity(_ suite: TestSuite) {
        let auth = codexAuth(account: "c0de-1", email: "c@example.com", plan: "plus")
        let token = (json(auth)["tokens"] as? [String: Any])?["id_token"] as? String ?? ""
        suite.expect((token.contains("-") || token.contains("_")) && !token.contains("=")
                        && CodexLogin.identity(auth) == CodexLogin.Identity(id: "c0de-1", email: "c@example.com", plan: "plus"),
                     "the login is read from the id token's claims, in the URL form of base64 and without padding")
        let bare = data(["tokens": ["id_token": [data(["alg": "none"]), data(["email": "d@example.com"]), Data()].map(base64URL)
            .joined(separator: "."), "account_id": "from-tokens"]])
        suite.expect(CodexLogin.identity(bare)?.id == "from-tokens" && CodexLogin.identity(Data(#"{"tokens":{"id_token":"a.b"}}"#.utf8)) == nil
                        && CodexLogin.claims("not.a!token.x") == nil,
                     "an older token names the account beside it, and a token that does not decode names nobody")

        let home = temporaryFolder("codex-identity")
        defer { try? FileManager.default.removeItem(at: home) }
        let adapter = CodexLoginAdapter(home: home, copies: CodexCredentialCopies(directory: home.appending(path: "copies")),
                                        limits: { _ in .failure(.missing) }, processes: { 3 })
        suite.expect(isNone { try adapter.readLive() } && adapter.runningSessions() == 3, "without an auth.json nobody is signed in")
        try? FileManager.default.createDirectory(at: home.appending(path: ".codex"), withIntermediateDirectories: true)
        try? Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-test","tokens":null}"#.utf8).write(to: CodexLogin.authURL(home: home))
        var unsupported = false
        do { _ = try adapter.readLive() } catch AgentLoginError.unsupported { unsupported = true } catch {}
        suite.expect(unsupported, "an API key's login has no plan to swap and is told apart from signed out")
        suite.expect(CodexLogin.isCodex("/Users/someone/.nvm/versions/node/v24/lib/node_modules/@openai/codex/vendor/codex/codex")
                        && CodexLogin.isCodex("/opt/homebrew/bin/codex-aarch64-apple-darwin")
                        && !CodexLogin.isCodex("/usr/local/bin/node") && !CodexLogin.isCodex("/Applications/Codex.app/Contents/MacOS/Codex"),
                     "a Codex session is counted by its tool's executable, not by the script or app that started it")
    }

    private static func codexSwitch(_ suite: TestSuite) {
        let home = temporaryFolder("codex")
        defer { try? FileManager.default.removeItem(at: home) }
        let live = CodexLogin.authURL(home: home)
        try? FileManager.default.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
        let copies = CodexCredentialCopies(directory: home.appending(path: "copies"))
        let store = AgentAccountStore(directory: home.appending(path: "store"), copies: [.codex: copies])
        let adapter = CodexLoginAdapter(home: home, copies: copies, limits: { _ in .failure(.missing) }, processes: { 0 })
        let switcher = AgentAccountSwitcher(store: store, adapters: [.codex: adapter])

        let first = codexAuth(account: "c0de-1", email: "one@example.com")
        let second = codexAuth(account: "c0de-2", email: "two@example.com", plan: "team")
        for auth in [first, second] {
            try? auth.write(to: live)
            _ = (try? adapter.readLive()).flatMap { try? store.capture($0, now: now) }
        }
        suite.expect(store.accounts.map(\.id) == ["c0de-1", "c0de-2"] && store.accounts.map(\.organization) == ["pro", "team"]
                        && store.accounts.allSatisfy { $0.identity.isEmpty },
                     "a Codex login is saved under its account id, with its plan for a name")

        // Codex refreshed the second login since it was saved.
        let rotated = codexAuth(account: "c0de-2", email: "two@example.com", plan: "team", refresh: "rt-2")
        try? rotated.write(to: live)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: live.path)
        let result = switcher.switch(to: "c0de-1")
        suite.expect(result == .success(.switched) && (try? Data(contentsOf: live)) == first && mode(live) == 0o600
                        && (try? FileManager.default.contentsOfDirectory(atPath: live.deletingLastPathComponent().path)) == ["auth.json"],
                     "a swap replaces auth.json whole and owner-only, leaving nothing else in the folder")
        suite.expect((try? copies.read("c0de-2")) == rotated && switcher.switch(to: "c0de-1") == .success(.alreadyActive),
                     "the login swapped away from is saved again with the tokens it had rotated to")

        try? FileManager.default.removeItem(at: live)
        suite.expect(switcher.switch(to: "c0de-2") == .success(.switched) && (try? Data(contentsOf: live)) == rotated
                        && (try? copies.read("c0de-1")) == first,
                     "a signed-out Codex is signed in by the swap")
        let key = Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-test","tokens":null}"#.utf8)
        try? key.write(to: live)
        suite.expect(switcher.switch(to: "c0de-1") == .failure(.unsupported) && (try? Data(contentsOf: live)) == key,
                     "an API key's login is not replaced")
    }
}
