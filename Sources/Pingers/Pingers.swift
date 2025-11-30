import SwiftUI
import AppKit
import PingersLib

@main
struct PingersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene - menu bar app has no windows
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var pingService: PingService?
    var pingScheduler: PingScheduler?
    var currentResult: PingResult?
    var lastCheckedTime: Date?
    var currentInterval: TimeInterval = 10.0
    var pingHistory: [PingResult] = [] // Track last 5 ping results
    var useMonospace: Bool = false
    var pingHost: String = "1.1.1.1"

    // UserDefaults keys
    private let intervalKey = "pingIntervalSeconds"
    private let monospaceFontKey = "useMonospaceFont"
    private let pingHostKey = "pingHost"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load saved preferences or use defaults
        let savedInterval = UserDefaults.standard.double(forKey: intervalKey)
        if savedInterval > 0 {
            currentInterval = savedInterval
        }

        useMonospace = UserDefaults.standard.bool(forKey: monospaceFontKey)

        if let savedHost = UserDefaults.standard.string(forKey: pingHostKey), !savedHost.isEmpty {
            pingHost = savedHost
        }

        // Create the status item in the menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = "Starting..."
            button.setAccessibilityLabel("Ping Status")
        }

        // Create initial menu
        updateMenu()

        // Initialize ping service and scheduler
        let service = PingService(host: pingHost)
        self.pingService = service

        let scheduler = PingScheduler(service: service, intervalSeconds: currentInterval) { [weak self] result in
            Task { @MainActor in
                self?.handlePingResult(result)
            }
        }
        self.pingScheduler = scheduler

        // Start pinging
        scheduler.start()
    }

    func updateMenu() {
        let menu = NSMenu()

        // Show current status
        if let result = currentResult {
            let statusText: String
            switch result {
            case .success(let latencyMs):
                statusText = String(format: "Latency: %.0f ms", latencyMs)
            case .timeout:
                statusText = "Status: Timeout"
            case .networkUnreachable:
                statusText = "Status: Unreachable"
            case .commandFailed(let reason):
                statusText = "Status: Failed"
                // Add error details as separate item
                let errorItem = NSMenuItem(title: "  \(reason)", action: nil, keyEquivalent: "")
                errorItem.isEnabled = false
                menu.addItem(errorItem)
            }

            let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        }

        // Show last checked time
        if let lastChecked = lastCheckedTime {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            formatter.dateStyle = .none
            let timeString = formatter.string(from: lastChecked)

            let timeItem = NSMenuItem(title: "Last checked: \(timeString)", action: nil, keyEquivalent: "")
            timeItem.isEnabled = false
            menu.addItem(timeItem)
        }

        // Display ping history (last 3 results)
        if !pingHistory.isEmpty {
            menu.addItem(NSMenuItem.separator())

            let historyHeader = NSMenuItem(title: "Recent History", action: nil, keyEquivalent: "")
            historyHeader.isEnabled = false
            menu.addItem(historyHeader)

            for historyResult in pingHistory {
                let historyItem = createHistoryMenuItem(for: historyResult)
                menu.addItem(historyItem)
            }
        }

        // Separator before actions
        menu.addItem(NSMenuItem.separator())

        // Settings submenu
        let settingsMenu = NSMenu()

        // Monospace font toggle
        let monospaceFontItem = NSMenuItem(title: "Use Monospace Font", action: #selector(toggleMonospaceFont), keyEquivalent: "")
        monospaceFontItem.state = useMonospace ? .on : .off
        settingsMenu.addItem(monospaceFontItem)

        // Service/host selection submenu
        let serviceMenu = NSMenu()
        let services: [(title: String, host: String)] = [
            ("1.1.1.1 (Cloudflare)", "1.1.1.1"),
            ("1.0.0.1 (Cloudflare)", "1.0.0.1"),
            ("8.8.8.8 (Google)", "8.8.8.8"),
            ("8.8.4.4 (Google)", "8.8.4.4"),
            ("9.9.9.9 (Quad9)", "9.9.9.9")
        ]

        let presetHosts = services.map { $0.host }
        let isCustomHost = !presetHosts.contains(pingHost)

        for (title, host) in services {
            let item = NSMenuItem(title: title, action: #selector(setPingHost(_:)), keyEquivalent: "")
            item.representedObject = host
            item.state = (pingHost == host) ? .on : .off
            serviceMenu.addItem(item)
        }

        // Show custom host if not a preset
        if isCustomHost {
            serviceMenu.addItem(NSMenuItem.separator())
            let customItem = NSMenuItem(title: "\(pingHost) (Custom)", action: nil, keyEquivalent: "")
            customItem.state = .on
            customItem.isEnabled = false
            serviceMenu.addItem(customItem)
        }

        serviceMenu.addItem(NSMenuItem.separator())
        serviceMenu.addItem(NSMenuItem(title: "Custom...", action: #selector(showCustomHostDialog), keyEquivalent: ""))

        let serviceMenuItem = NSMenuItem(title: "Ping Service", action: nil, keyEquivalent: "")
        serviceMenuItem.submenu = serviceMenu
        settingsMenu.addItem(serviceMenuItem)

        let settingsMenuItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsMenuItem.submenu = settingsMenu
        menu.addItem(settingsMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Interval preferences submenu
        let intervalMenu = NSMenu()
        let intervals: [(title: String, value: TimeInterval)] = [
            ("500 ms", 0.5),
            ("1 second", 1.0),
            ("2 seconds", 2.0),
            ("5 seconds", 5.0),
            ("10 seconds", 10.0),
            ("30 seconds", 30.0),
            ("60 seconds", 60.0)
        ]

        for (title, value) in intervals {
            let item = NSMenuItem(title: title, action: #selector(setInterval(_:)), keyEquivalent: "")
            item.representedObject = value
            item.state = (abs(currentInterval - value) < 0.1) ? .on : .off
            intervalMenu.addItem(item)
        }

        let intervalMenuItem = NSMenuItem(title: "Check Interval", action: nil, keyEquivalent: "")
        intervalMenuItem.submenu = intervalMenu
        menu.addItem(intervalMenuItem)

        // Refresh action
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))

        // Quit action
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    func createHistoryMenuItem(for result: PingResult) -> NSMenuItem {
        let (text, color): (String, NSColor)

        switch result {
        case .success(let latencyMs):
            text = String(format: "%.0f ms", latencyMs)
            // Apply same color coding as status item
            if latencyMs < 100 {
                color = .labelColor // Default text color
            } else if latencyMs < 200 {
                color = .systemYellow
            } else {
                color = .systemRed
            }

        case .timeout:
            text = "Timeout"
            color = .systemRed

        case .networkUnreachable:
            text = "Unreachable"
            color = .systemRed

        case .commandFailed:
            text = "Failed"
            color = .systemRed
        }

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false

        // Apply color to menu item title
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color
        ]
        item.attributedTitle = NSAttributedString(string: "  \(text)", attributes: attributes)

        return item
    }

    @objc func setInterval(_ sender: NSMenuItem) {
        guard let newInterval = sender.representedObject as? TimeInterval else { return }

        // Save to UserDefaults
        UserDefaults.standard.set(newInterval, forKey: intervalKey)
        currentInterval = newInterval

        // Recreate scheduler with new interval
        guard let service = pingService else { return }

        pingScheduler?.stop()
        let scheduler = PingScheduler(service: service, intervalSeconds: newInterval) { [weak self] result in
            Task { @MainActor in
                self?.handlePingResult(result)
            }
        }
        self.pingScheduler = scheduler
        scheduler.start()

        // Update menu to show new selection
        updateMenu()
    }

    @objc func toggleMonospaceFont() {
        useMonospace.toggle()
        UserDefaults.standard.set(useMonospace, forKey: monospaceFontKey)

        // Update display with new font preference
        if let result = currentResult {
            handlePingResult(result)
        }

        updateMenu()
    }

    @objc func setPingHost(_ sender: NSMenuItem) {
        guard let newHost = sender.representedObject as? String else { return }
        applyPingHost(newHost)
    }

    @objc func showCustomHostDialog() {
        let alert = NSAlert()
        alert.messageText = "Custom Ping Service"
        alert.informativeText = "Enter a hostname or IP address to ping:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = pingHost
        textField.placeholderString = "e.g., example.com or 192.168.1.1"
        alert.accessoryView = textField

        alert.window.initialFirstResponder = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newHost = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !newHost.isEmpty {
                applyPingHost(newHost)
            }
        }
    }

    private func applyPingHost(_ newHost: String) {
        // Save to UserDefaults
        UserDefaults.standard.set(newHost, forKey: pingHostKey)
        pingHost = newHost

        // Recreate service and scheduler with new host
        pingScheduler?.stop()

        let service = PingService(host: newHost)
        self.pingService = service

        let scheduler = PingScheduler(service: service, intervalSeconds: currentInterval) { [weak self] result in
            Task { @MainActor in
                self?.handlePingResult(result)
            }
        }
        self.pingScheduler = scheduler
        scheduler.start()

        // Update menu to show new selection
        updateMenu()
    }

    @objc func refreshNow() {
        Task { @MainActor in
            guard let service = pingService else { return }
            let result = await service.ping()
            handlePingResult(result)
        }
    }

    func handlePingResult(_ result: PingResult) {
        currentResult = result
        lastCheckedTime = Date()

        // Add to history with rotation (keep last 3)
        pingHistory.append(result)
        if pingHistory.count > 5 {
            pingHistory.removeFirst()
        }

        guard let button = statusItem?.button else { return }

        // Determine text and color based on result
        let (text, color, accessibilityLabel): (String, NSColor, String)

        switch result {
        case .success(let latencyMs):
            text = String(format: "%.0f ms", latencyMs)
            // Color scheme: default for <100ms, yellow for 100-199ms, red for ≥200ms
            if latencyMs < 100 {
                color = .labelColor // Default text color
            } else if latencyMs < 200 {
                color = .systemYellow
            } else {
                color = .systemRed
            }
            accessibilityLabel = String(format: "Ping: %.0f milliseconds", latencyMs)

        case .timeout:
            text = "Timeout"
            color = .systemRed
            accessibilityLabel = "Ping: Timeout"

        case .networkUnreachable:
            text = "Unreachable"
            color = .systemRed
            accessibilityLabel = "Ping: Network unreachable"

        case .commandFailed:
            text = "Failed"
            color = .systemRed
            accessibilityLabel = "Ping: Command failed"
        }

        // Apply color and font to button title
        let font: NSFont = useMonospace
            ? NSFont.monospacedSystemFont(ofSize: 0, weight: .regular)
            : NSFont.systemFont(ofSize: 0)

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: font
        ]
        button.attributedTitle = NSAttributedString(string: text, attributes: attributes)
        button.setAccessibilityLabel(accessibilityLabel)

        // Update menu with new details
        updateMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pingScheduler?.stop()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}
