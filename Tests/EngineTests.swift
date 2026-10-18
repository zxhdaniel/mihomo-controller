import Foundation

final class FakeMachine: Machine {
    var loaded = true
    var running = true
    var failOnce: String?
    var log: [[String]] = []
    var unsafeStop = false
    var settings = ["web", "secureweb", "socksfirewall"].map { ProxySetting($0, "Enabled: Yes\nServer: 127.0.0.1\nPort: 7890") }
    func run(_ program: String, _ args: [String]) -> CommandResult {
        log.append(args)
        if args.first == failOnce { failOnce = nil; return .init(code: 1, output: "fixture: failed") }
        if program.hasSuffix("launchctl") {
            switch args.first {
            case "print": return .init(code: loaded ? 0 : 1, output: "")
            case "print-disabled": return .init(code: 0, output: "{}")
            case "bootstrap": loaded = true; running = true
            case "kickstart": running = true
            case "bootout": unsafeStop = settings.contains { $0.owned && $0.enabled }; loaded = false; running = false
            default: break
            }
        }
        if program.hasSuffix("networksetup") {
            if args.first == "-getautoproxyurl" { return .init(code: 0, output: "Enabled: No") }
            for i in settings.indices {
                let kind = settings[i].kind
                if args.first == "-get\(kind)proxy" {
                    let s = settings[i]
                    return .init(code: 0, output: "Enabled: \(s.enabled ? "Yes" : "No")\nServer: \(s.server)\nPort: \(s.port)")
                }
                if args.first == "-set\(kind)proxy" {
                    settings[i].server = args[2]; settings[i].port = Int(args[3])!; settings[i].enabled = true
                }
                if args.first == "-set\(kind)proxystate" { settings[i].enabled = args[2] == "on" }
            }
        }
        return .init(code: 0, output: "")
    }
    func core(_ route: String) -> [String: Any]? {
        guard running else { return nil }
        if route == "/version" { return ["meta": true, "version": "test"] }
        if route == "/configs" { return ["mixed-port": 7890] }
        return ["proxies": ["PROXY": ["now": "test node"]]]
    }
}

func runTests() {
    var count = 0
    func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { print("FAIL: \(name)"); exit(1) }
        count += 1; print("PASS: \(name)")
    }
    do {
        let machine = FakeMachine(); let engine = Engine(machine)
        try engine.stop()
        expect(!machine.running && !machine.loaded, "stop unloads managed core")
        expect(machine.settings.allSatisfy { !$0.enabled }, "stop disables all owned system proxies")
        expect(!machine.unsafeStop, "system proxies are disabled before core stops")
        expect(!machine.log.contains { $0.contains("Karing (system)") }, "start and stop never change Karing")
        try engine.start()
        expect(machine.running && machine.loaded, "start bootstraps stopped service")
        expect(machine.settings.allSatisfy { $0.owned && $0.enabled }, "start enables three system proxies")
        let snapshot = try engine.state()
        expect(snapshot.enabled, "snapshot reports enabled state")

        let failing = FakeMachine(); failing.failOnce = "-setwebproxystate"
        do { try Engine(failing).stop(); expect(false, "stop must fail when proxy disable fails") }
        catch { expect(failing.running && !failing.log.contains { $0.first == "bootout" }, "failed proxy disable leaves core running") }

        let external = FakeMachine()
        external.settings = external.settings.map { ProxySetting($0.kind, "Enabled: Yes\nServer: 127.0.0.1\nPort: 3067") }
        try Engine(external).stop()
        expect(external.settings.allSatisfy { $0.enabled && $0.port == 3067 }, "another client’s proxy is preserved")

        let rollback = FakeMachine(); rollback.loaded = false; rollback.running = false
        rollback.settings = rollback.settings.map { ProxySetting($0.kind, "Enabled: No\nServer: 127.0.0.1\nPort: 3067") }
        rollback.failOnce = "-setsecurewebproxystate"
        do { try Engine(rollback).start(); expect(false, "partial start must fail") }
        catch {
            expect(rollback.settings.allSatisfy { !$0.enabled && $0.port == 3067 }, "failed start restores prior proxy settings")
            expect(!rollback.running && !rollback.unsafeStop, "failed start stops only newly loaded core after rollback")
        }
        print("\(count) checks passed; no live network settings changed.")
    } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
}
