import Cocoa
import Network

// Menu-bar app: turns Wi-Fi off when a wired connection is active, back on when it's gone.
// No dependencies. All detection reuses the same networksetup/ifconfig logic as the shell version.

let kEnabled = "automaticSwitchingEnabled"

func run(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    p.waitUntilExit()
    let d = out.fileHandleForReading.readDataToEndOfFile()
    return String(data: d, encoding: .utf8) ?? ""
}

// Wi-Fi device name, e.g. "en0".
func wifiDevice() -> String? {
    let lines = run("/usr/sbin/networksetup", ["-listallhardwareports"])
        .components(separatedBy: "\n")
    for (i, line) in lines.enumerated() where line.contains("Wi-Fi") {
        if i + 1 < lines.count {
            let parts = lines[i + 1].components(separatedBy: " ")
            if let dev = parts.last, !dev.isEmpty { return dev }
        }
    }
    return nil
}

// Any non-Wi-Fi device with an active link AND an IPv4 address counts as "on ethernet".
func onEthernet(wifiDev: String) -> Bool {
    let devices = run("/usr/sbin/networksetup", ["-listallhardwareports"])
        .components(separatedBy: "\n")
        .filter { $0.hasPrefix("Device:") }
        .compactMap { $0.components(separatedBy: " ").last }
    for dev in devices where dev != wifiDev && !dev.isEmpty {
        let active = run("/sbin/ifconfig", [dev]).contains("status: active")
        let hasIP = !run("/usr/sbin/ipconfig", ["getifaddr", dev])
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if active && hasIP { return true }
    }
    return false
}

func wifiIsOn(_ dev: String) -> Bool {
    run("/usr/sbin/networksetup", ["-getairportpower", dev]).contains(": On")
}

func setWifi(_ dev: String, on: Bool) {
    _ = run("/usr/sbin/networksetup", ["-setairportpower", dev, on ? "on" : "off"])
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let monitor = NWPathMonitor()
    var ethernetActive = false

    var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: kEnabled) == nil { return true }
            return UserDefaults.standard.bool(forKey: kEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: kEnabled) }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        removeLegacyAgent()  // clean up the old shell-based launch agent if present
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // React to any network change, then re-check (small delay: DHCP/IP lags link-up).
        monitor.pathUpdateHandler = { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.apply() }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        apply()
    }

    func apply() {
        guard let wifi = wifiDevice() else { updateUI(); return }
        ethernetActive = onEthernet(wifiDev: wifi)
        if enabled {
            let wantWifiOn = !ethernetActive
            if wifiIsOn(wifi) != wantWifiOn { setWifi(wifi, on: wantWifiOn) }
        }
        updateUI()
    }

    func updateUI() {
        let symbol: String
        if !enabled { symbol = "pause.circle" }
        else if ethernetActive { symbol = "cable.connector" }
        else { symbol = "antenna.radiowaves.left.and.right" }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Wi-Fi switcher")
        img?.isTemplate = true
        statusItem.button?.image = img
    }

    // MARK: Menu (rebuilt each time it opens so state is fresh)
    func menuNeedsUpdate(_ menu: NSMenu) {
        apply()
        menu.removeAllItems()
        let state = enabled
            ? (ethernetActive ? "Ethernet connected — Wi-Fi off" : "No ethernet — Wi-Fi on")
            : "Automatic switching is off"
        let header = NSMenuItem(title: state, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Automatic switching", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = enabled ? .on : .off
        menu.addItem(toggle)

        let login = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = loginEnabled() ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let uninstall = NSMenuItem(title: "Uninstall…", action: #selector(uninstallApp), keyEquivalent: "")
        uninstall.target = self
        menu.addItem(uninstall)
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc func uninstallApp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Uninstall Ethernet Wi-Fi Switcher?"
        alert.informativeText = "Wi-Fi will be turned back on, the app will stop starting at login, and it will be moved to the Trash."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let w = wifiDevice() { setWifi(w, on: true) }        // leave Wi-Fi usable
        if loginEnabled() {                                     // remove start-at-login
            _ = run("/bin/launchctl", ["unload", loginPlistURL.path])
            try? FileManager.default.removeItem(at: loginPlistURL)
        }
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    @objc func toggleEnabled() {
        enabled.toggle()
        apply()
    }

    // MARK: Start at login — a tiny LaunchAgent that `open`s this app bundle.
    var loginPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.user.ethernetwifiswitcher.plist")
    }

    func loginEnabled() -> Bool { FileManager.default.fileExists(atPath: loginPlistURL.path) }

    @objc func toggleLogin() {
        if loginEnabled() {
            _ = run("/bin/launchctl", ["unload", loginPlistURL.path])
            try? FileManager.default.removeItem(at: loginPlistURL)
        } else {
            let appPath = Bundle.main.bundlePath
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key><string>com.user.ethernetwifiswitcher</string>
                <key>ProgramArguments</key>
                <array><string>/usr/bin/open</string><string>\(appPath)</string></array>
                <key>RunAtLoad</key><true/>
            </dict>
            </plist>
            """
            try? plist.write(to: loginPlistURL, atomically: true, encoding: .utf8)
            _ = run("/bin/launchctl", ["load", loginPlistURL.path])
        }
    }

    // Remove the earlier shell-script launch agent so it doesn't fight this app.
    func removeLegacyAgent() {
        let legacy = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.user.wifi-off-on-ethernet.plist")
        if FileManager.default.fileExists(atPath: legacy.path) {
            _ = run("/bin/launchctl", ["unload", legacy.path])
            try? FileManager.default.removeItem(at: legacy)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
