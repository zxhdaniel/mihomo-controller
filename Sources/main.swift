import Cocoa

let ink = NSColor(srgbRed: 0.12, green: 0.19, blue: 0.28, alpha: 1)
let blue = NSColor(srgbRed: 0.18, green: 0.34, blue: 0.79, alpha: 1)
let muted = NSColor(srgbRed: 0.43, green: 0.49, blue: 0.57, alpha: 1)
let green = NSColor(srgbRed: 0.12, green: 0.49, blue: 0.39, alpha: 1)
let red = NSColor(srgbRed: 0.69, green: 0.25, blue: 0.20, alpha: 1)
let paper = NSColor(srgbRed: 0.95, green: 0.965, blue: 0.985, alpha: 1)

final class RouteView: NSView {
    var connected = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let points: [CGFloat] = [34, bounds.midX, bounds.width - 34]
        let line = NSBezierPath()
        line.move(to: NSPoint(x: points[0], y: 18)); line.line(to: NSPoint(x: points[2], y: 18))
        (connected ? green.withAlphaComponent(0.35) : muted.withAlphaComponent(0.2)).setStroke()
        line.lineWidth = 2; line.stroke()
        for (i, x) in points.enumerated() {
            let circle = NSBezierPath(ovalIn: NSRect(x: x - 6, y: 12, width: 12, height: 12))
            (connected ? green : muted.withAlphaComponent(0.45)).setFill(); circle.fill()
            let text = ["应用", "Mihomo", "网络"][i] as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: i == 1 ? .semibold : .regular), .foregroundColor: connected ? ink : muted]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: x - size.width / 2, y: 36), withAttributes: attributes)
        }
    }
}

final class Panel: NSView {
    let headline = NSTextField(labelWithString: "正在读取状态…")
    let subtitle = NSTextField(wrappingLabelWithString: "")
    let route = RouteView()
    let values = (0..<4).map { _ in NSTextField(labelWithString: "—") }
    let start = NSButton(title: "启用 Mihomo 代理", target: nil, action: nil)
    let stop = NSButton(title: "安全停止", target: nil, action: nil)
    let dashboard = NSButton(title: "打开节点面板 ↗", target: nil, action: nil)
    let message = NSTextField(wrappingLabelWithString: "")
    let footnote = NSTextField(labelWithString: "")
    let spinner = NSProgressIndicator()
    override var isFlipped: Bool { true }
    func label(_ text: String, _ frame: NSRect, _ font: NSFont, _ color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame; label.font = font; label.textColor = color; addSubview(label)
        return label
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.backgroundColor = paper.cgColor
        let icon = NSImageView(frame: NSRect(x: 30, y: 27, width: 34, height: 34))
        icon.image = NSImage(systemSymbolName: "arrow.left.arrow.right.circle.fill", accessibilityDescription: "Mihomo")
        icon.contentTintColor = blue; addSubview(icon)
        _ = label("Mihomo", NSRect(x: 76, y: 25, width: 250, height: 26), .systemFont(ofSize: 20, weight: .semibold), ink)
        _ = label("本机代理控制器", NSRect(x: 77, y: 52, width: 260, height: 20), .systemFont(ofSize: 12), muted)
        dashboard.frame = NSRect(x: 420, y: 32, width: 130, height: 26)
        dashboard.isBordered = false; dashboard.contentTintColor = blue; dashboard.font = .systemFont(ofSize: 12)
        addSubview(dashboard)
        headline.frame = NSRect(x: 30, y: 98, width: 485, height: 38)
        headline.font = .systemFont(ofSize: 29, weight: .semibold); headline.textColor = ink; addSubview(headline)
        spinner.frame = NSRect(x: 527, y: 107, width: 18, height: 18)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false; addSubview(spinner)
        subtitle.frame = NSRect(x: 31, y: 145, width: 515, height: 38)
        subtitle.font = .systemFont(ofSize: 13); subtitle.textColor = muted; addSubview(subtitle)
        route.frame = NSRect(x: 30, y: 192, width: 520, height: 60); addSubview(route)
        let details = NSView(frame: NSRect(x: 30, y: 275, width: 520, height: 136))
        details.wantsLayer = true; details.layer?.backgroundColor = NSColor.white.cgColor
        details.layer?.cornerRadius = 12; details.layer?.borderWidth = 1
        details.layer?.borderColor = ink.withAlphaComponent(0.07).cgColor; addSubview(details)
        for i in 0..<4 {
            let y = CGFloat(285 + i * 32)
            _ = label(["内核状态", "系统代理 · Wi-Fi", "当前节点", "Karing VPN"][i], NSRect(x: 46, y: y, width: 145, height: 20), .systemFont(ofSize: 12), muted)
            let value = values[i]; value.frame = NSRect(x: 190, y: y, width: 342, height: 21)
            value.font = i == 2 ? .systemFont(ofSize: 12) : .monospacedSystemFont(ofSize: 12, weight: .medium)
            value.textColor = ink; value.alignment = .right; value.lineBreakMode = .byTruncatingMiddle
            addSubview(value)
        }
        start.frame = NSRect(x: 28, y: 432, width: 326, height: 42)
        start.bezelStyle = .rounded; start.controlSize = .large; start.bezelColor = blue
        start.contentTintColor = .white; start.font = .systemFont(ofSize: 14, weight: .semibold)
        start.keyEquivalent = "\r"; addSubview(start)
        stop.frame = NSRect(x: 364, y: 432, width: 188, height: 42)
        stop.bezelStyle = .rounded; stop.controlSize = .large; stop.contentTintColor = red
        stop.font = .systemFont(ofSize: 14, weight: .medium); addSubview(stop)
        message.frame = NSRect(x: 31, y: 486, width: 515, height: 37)
        message.font = .systemFont(ofSize: 12); message.textColor = muted; addSubview(message)
        footnote.frame = NSRect(x: 31, y: 539, width: 515, height: 19)
        footnote.font = .systemFont(ofSize: 11); footnote.textColor = muted; addSubview(footnote)
    }
    required init?(coder: NSCoder) { fatalError() }
    func show(_ s: Snapshot, busy: Bool, notice: String? = nil) {
        if s.enabled {
            headline.stringValue = "代理已启用"; headline.textColor = green
            subtitle.stringValue = "支持系统代理的应用，正通过 Mihomo 连接网络。"
        } else if !s.ready && s.proxyCount > 0 {
            headline.stringValue = "代理等待恢复"; headline.textColor = red
            subtitle.stringValue = "系统代理仍指向 Mihomo。可以重新启用，或安全停止。"
        } else if s.running {
            headline.stringValue = "内核运行中"; headline.textColor = ink
            subtitle.stringValue = "\(s.proxyCount == 0 ? "系统代理尚未启用" : "部分系统代理已启用")。点击启用，让应用通过 Mihomo 上网。"
        } else {
            headline.stringValue = "Mihomo 已停止"; headline.textColor = ink
            subtitle.stringValue = "点击启用后，会先启动内核，再打开系统代理。"
        }
        route.connected = s.enabled
        values[0].stringValue = s.running ? "运行中 · \(s.version)" : "已停止"
        values[1].stringValue = s.proxyCount == 3 ? "已启用 · 127.0.0.1:7890" : (s.proxyCount > 0 ? "部分启用 · \(s.proxyCount)/3" : (s.otherProxy ? "由其他代理接管" : "未启用"))
        values[2].stringValue = s.node
        values[3].stringValue = s.karing
        values[3].textColor = s.karing == "已连接" ? blue : muted
        start.isEnabled = !busy && !s.enabled
        stop.isEnabled = !busy && (s.running || s.loaded || s.proxyCount > 0)
        dashboard.isEnabled = s.running
        message.stringValue = notice ?? "启用与停止只管理 Mihomo；Karing 保持当前状态。"
        message.textColor = notice == nil ? muted : ink
        footnote.stringValue = (s.autostart ? "内核将在下次登录时自动启动。" : "内核的登录自动启动已关闭。") + "关闭此窗口不影响代理。"
        busy ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var panel: Panel!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var busy = false
    var refreshing = false
    var last = Snapshot()
    var notice: String?
    let engine = Engine()
    let queue = DispatchQueue(label: "local.mihomo.control")
    var startMenu: NSMenuItem!
    var stopMenu: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(), appMenu = NSMenu(), holder = NSMenuItem()
        appMenu.addItem(withTitle: "关于 Mihomo 控制器", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出控制器（保留代理）", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        holder.submenu = appMenu; menu.addItem(holder); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 570), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Mihomo 控制器"; window.isReleasedWhenClosed = false
        panel = Panel(frame: NSRect(x: 0, y: 0, width: 580, height: 570)); window.contentView = panel
        panel.start.target = self; panel.start.action = #selector(start)
        panel.stop.target = self; panel.stop.action = #selector(stop)
        panel.dashboard.target = self; panel.dashboard.action = #selector(dashboard)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.left.arrow.right.circle", accessibilityDescription: "Mihomo 控制器")
        let tray = NSMenu()
        tray.addItem(withTitle: "打开控制器", action: #selector(openWindow), keyEquivalent: "")
        tray.addItem(.separator())
        startMenu = tray.addItem(withTitle: "启用 Mihomo 代理", action: #selector(start), keyEquivalent: "")
        stopMenu = tray.addItem(withTitle: "安全停止 Mihomo", action: #selector(stop), keyEquivalent: "")
        tray.addItem(withTitle: "打开节点面板", action: #selector(dashboard), keyEquivalent: "")
        tray.addItem(.separator())
        tray.addItem(withTitle: "退出控制器（保留代理）", action: #selector(quitController), keyEquivalent: "")
        for item in tray.items { item.target = self }
        tray.autoenablesItems = false; statusItem.menu = tray
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func render() {
        panel.show(last, busy: busy, notice: notice)
        startMenu?.isEnabled = !busy && !last.enabled
        stopMenu?.isEnabled = !busy && (last.running || last.loaded || last.proxyCount > 0)
        statusItem?.button?.toolTip = last.enabled ? "Mihomo：代理已启用" : (last.running ? "Mihomo：内核运行中" : "Mihomo：已停止")
        statusItem?.button?.image = NSImage(systemSymbolName: last.enabled ? "arrow.left.arrow.right.circle.fill" : "arrow.left.arrow.right.circle", accessibilityDescription: "Mihomo")
    }
    func refresh() {
        guard !busy && !refreshing else { return }
        refreshing = true
        queue.async {
            let result = Result { try self.engine.state() }
            DispatchQueue.main.async {
                self.refreshing = false
                switch result {
                case .success(let snapshot): self.last = snapshot
                case .failure(let error): self.notice = error.localizedDescription
                }
                self.render()
            }
        }
    }
    func perform(_ starting: Bool) {
        guard !busy else { return }
        busy = true; notice = starting ? "正在启动内核并启用系统代理…" : "正在关闭系统代理并停止内核…"; render()
        queue.async {
            let result = Result { if starting { try self.engine.start() } else { try self.engine.stop() } }
            let snapshot = try? self.engine.state()
            DispatchQueue.main.async {
                self.busy = false
                if let snapshot = snapshot { self.last = snapshot }
                switch result {
                case .success: self.notice = starting ? "系统代理已启用。可以开始上网。" : "系统代理已关闭，Mihomo 内核已停止。"
                case .failure(let error):
                    self.notice = "操作未完成，请查看提示。"
                    self.openWindow()
                    let alert = NSAlert(); alert.messageText = "操作未完成"; alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning; alert.addButton(withTitle: "知道了"); alert.beginSheetModal(for: self.window)
                }
                self.render()
            }
        }
    }
    @objc func start() { perform(true) }
    @objc func stop() { perform(false) }
    @objc func quitController() { NSApp.terminate(nil) }
    @objc func openWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func dashboard() { NSWorkspace.shared.open(URL(string: "http://127.0.0.1:9090/ui/")!) }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Mihomo 控制器", .applicationVersion: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"), .credits: NSAttributedString(string: "本机状态、启用代理与安全停止。\n管理 Wi-Fi 系统代理；不改动 Karing。")])
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openWindow(); return true }
}

if CommandLine.arguments.contains("--self-test") {
    runTests()
} else if CommandLine.arguments.contains("--status-json") {
    let result = try Engine().state()
    let data = try JSONSerialization.data(withJSONObject: ["running": result.running, "proxyEnabled": result.enabled, "node": result.node, "karing": result.karing], options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
} else if let flag = CommandLine.arguments.firstIndex(of: "--render-preview") {
    _ = NSApplication.shared
    let panel = Panel(frame: NSRect(x: 0, y: 0, width: 580, height: 570))
    var sample = Snapshot(); sample.running = true; sample.ready = true; sample.version = "v1.19.32"; sample.node = "示例节点 · Singapore"
    sample.proxies = ["web", "secureweb", "socksfirewall"].map { ProxySetting($0, "Enabled: Yes\nServer: 127.0.0.1\nPort: 7890") }
    if CommandLine.arguments.contains("--stopped") { sample.running = false; sample.node = "—"; sample.proxies = [] }
    panel.show(sample, busy: false)
    let window = NSWindow(contentRect: panel.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = panel; panel.layoutSubtreeIfNeeded()
    let bitmap = panel.bitmapImageRepForCachingDisplay(in: panel.bounds)!
    panel.cacheDisplay(in: panel.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
} else {
    let app = NSApplication.shared
    if let other = NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.zxhdaniel.mihomo-controller").first(where: { $0.processIdentifier != getpid() }) {
        other.activate(options: []); exit(0)
    }
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate(); app.delegate = delegate; app.run()
}
