import Foundation
import SystemConfiguration

struct CommandResult {
    var code: Int32
    var output: String
}

protocol Machine {
    func run(_ program: String, _ arguments: [String]) -> CommandResult
    func core(_ route: String) -> [String: Any]?
}

extension Machine {
    func proxyReady() -> Bool {
        guard core("/version")?["meta"] as? Bool == true,
              core("/configs")?["mixed-port"] as? Int == 7890 else { return false }
        return run("/usr/bin/nc", ["-z", "-G", "1", "127.0.0.1", "7890"]).code == 0
    }
}

final class LocalMachine: Machine {
    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String: Any]?
        func set(_ value: [String: Any]?) { lock.lock(); defer { lock.unlock() }; stored = value }
        func get() -> [String: Any]? { lock.lock(); defer { lock.unlock() }; return stored }
    }
    func run(_ program: String, _ arguments: [String]) -> CommandResult {
        let process = Process(), pipe = Pipe(), done = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return .init(code: -1, output: error.localizedDescription) }
        if done.wait(timeout: .now() + 12) == .timedOut {
            process.terminate()
            return .init(code: -1, output: "操作超时，请检查系统是否正在等待授权。")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return .init(code: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
    }

    func core(_ route: String) -> [String: Any]? {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 1.2
        config.timeoutIntervalForResource = 1.5
        let session = URLSession(configuration: config)
        let done = DispatchSemaphore(value: 0)
        let answer = ResponseBox()
        let task = session.dataTask(with: URL(string: "http://127.0.0.1:9090" + route)!) { data, response, _ in
            if let response = response as? HTTPURLResponse, response.statusCode == 200, let data = data {
                answer.set((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
            }
            done.signal()
        }
        task.resume()
        if done.wait(timeout: .now() + 2) == .timedOut { task.cancel() }
        session.invalidateAndCancel()
        return answer.get()
    }
}

struct ProxySetting {
    let kind: String
    var enabled = false
    var server = ""
    var port = 0
    var owned: Bool { ["127.0.0.1", "localhost", "::1"].contains(server) && port == 7890 }
    init(_ kind: String, _ text: String) {
        self.kind = kind
        for line in text.components(separatedBy: .newlines) {
            let pair = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2 else { continue }
            switch pair[0] {
            case "Enabled": enabled = pair[1] == "Yes"
            case "Server": server = pair[1]
            case "Port": port = Int(pair[1]) ?? 0
            default: break
            }
        }
    }
}

struct Snapshot {
    var running = false
    var ready = false
    var loaded = false
    var version = ""
    var node = "—"
    var proxies: [ProxySetting] = []
    var karing = "未连接"
    var autostart = true
    var proxyCount: Int { proxies.filter { $0.enabled && $0.owned }.count }
    var otherProxy: Bool { proxies.contains { $0.enabled && !$0.owned } }
    var enabled: Bool { running && ready && proxyCount == 3 }
}

struct ControlError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

final class Engine {
    let machine: Machine
    let domain = "gui/\(getuid())"
    let label = "com.mihomo.proxy"
    let service = "Wi-Fi"
    let agent: String
    let kinds = ["web", "secureweb", "socksfirewall"]
    var target: String { domain + "/" + label }
    init(_ machine: Machine = LocalMachine()) {
        self.machine = machine
        agent = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/com.mihomo.proxy.plist").path
    }
    func launch(_ args: [String]) -> CommandResult { machine.run("/bin/launchctl", args) }
    func network(_ args: [String]) -> CommandResult { machine.run("/usr/sbin/networksetup", args) }
    func checked(_ result: CommandResult, _ message: String) throws {
        if result.code != 0 || result.output.contains("Error:") || result.output.contains("You must be") {
            throw ControlError(message: message + "\n" + result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    func proxies() throws -> [ProxySetting] {
        try kinds.map { kind in
            let result = network(["-get\(kind)proxy", service])
            try checked(result, "无法读取 Wi-Fi 的系统代理。")
            guard result.output.contains("Enabled:") else { throw ControlError(message: "未找到 Wi-Fi 的代理设置。") }
            return ProxySetting(kind, result.output)
        }
    }
    func state() throws -> Snapshot {
        var result = Snapshot()
        result.loaded = launch(["print", target]).code == 0
        if let version = machine.core("/version"), version["meta"] as? Bool == true {
            result.running = true
            result.ready = machine.proxyReady()
            result.version = version["version"] as? String ?? ""
            if let proxies = machine.core("/proxies")?["proxies"] as? [String: [String: Any]] {
                result.node = proxies["PROXY"]?["now"] as? String ?? "—"
            }
        }
        result.proxies = try proxies()
        let vpn = machine.run("/usr/sbin/scutil", ["--nc", "status", "Karing (system)"]).output
        if vpn.hasPrefix("Connected") { result.karing = "已连接" }
        else if vpn.hasPrefix("Connecting") { result.karing = "连接中" }
        let disabled = launch(["print-disabled", domain]).output
        result.autostart = !disabled.contains("\"\(label)\" => true")
        return result
    }
    func restore(_ settings: [ProxySetting]) {
        for item in settings {
            if !item.server.isEmpty && item.port > 0 {
                _ = network(["-set\(item.kind)proxy", service, item.server, String(item.port)])
            }
            _ = network(["-set\(item.kind)proxystate", service, item.enabled ? "on" : "off"])
        }
    }
    func start() throws {
        let before = try proxies()
        let pac = network(["-getautoproxyurl", service])
        if pac.output.contains("Enabled: Yes") {
            throw ControlError(message: "Wi-Fi 当前启用了自动代理。请先在系统设置的「代理」中关闭自动代理，再启用 Mihomo。")
        }
        let wasLoaded = launch(["print", target]).code == 0
        try checked(launch(["enable", target]), "无法启用 Mihomo 服务。")
        do {
            if !wasLoaded { try checked(launch(["bootstrap", domain, agent]), "无法启动 Mihomo。请确认内核及启动配置仍在原位置。") }
            try checked(launch(["kickstart", target]), "无法启动 Mihomo 内核。")
            var ready = false
            for _ in 0..<20 {
                if machine.proxyReady() { ready = true; break }
                Thread.sleep(forTimeInterval: 0.2)
            }
            guard ready else { throw ControlError(message: "内核未能就绪，系统代理保持原状。请检查 Mihomo 日志。") }
            // Enable only after the core is accepting connections.
            for kind in kinds {
                try checked(network(["-set\(kind)proxy", service, "127.0.0.1", "7890"]), "无法设置系统代理。")
                try checked(network(["-set\(kind)proxystate", service, "on"]), "无法启用系统代理。")
            }
            let after = try proxies()
            guard after.allSatisfy({ $0.enabled && $0.owned }) else { throw ControlError(message: "系统代理未能全部启用，已尝试恢复原设置。") }
        } catch {
            restore(before)
            if !wasLoaded { _ = launch(["bootout", target]) }
            throw error
        }
    }
    func stop() throws {
        // Do not disable another client's proxy, and never stop the core while its system proxy is active.
        for item in try proxies() where item.enabled && item.owned {
            try checked(network(["-set\(item.kind)proxystate", service, "off"]), "系统代理未能关闭，Mihomo 保持运行。")
        }
        guard !(try proxies()).contains(where: { $0.enabled && $0.owned }) else {
            throw ControlError(message: "系统代理仍在使用 Mihomo，已取消停止内核。")
        }
        if launch(["print", target]).code == 0 {
            try checked(launch(["bootout", target]), "系统代理已关闭，但 Mihomo 服务未能停止。")
        }
        for _ in 0..<10 {
            if machine.core("/version") == nil { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw ControlError(message: "系统代理已关闭，但本地端口仍有内核运行。它可能由其他程序启动，本工具没有结束该进程。")
    }
}
