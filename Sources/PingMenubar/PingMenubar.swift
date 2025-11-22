import SwiftUI
import AppKit
import PingMenubarLib

@main
struct PingMenubarApp: App {
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
    var pingHistory: [PingResult] = [] // Track last 3 ping results

    // UserDefaults key for interval preference
    private let intervalKey = "pingIntervalSeconds"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load saved interval preference or use default
        let savedInterval = UserDefaults.standard.double(forKey: intervalKey)
        if savedInterval > 0 {
            currentInterval = savedInterval
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
        let service = PingService()
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

        // Apply color and monospaced font to button title
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.monospacedSystemFont(ofSize: 0, weight: .regular)
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
