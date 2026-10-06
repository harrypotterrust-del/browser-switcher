import AppKit

// MARK: - Browser model

struct Browser: Equatable {
    let url: URL
    let name: String
    let bundleID: String

    static func == (l: Browser, r: Browser) -> Bool { l.url == r.url }
}

// MARK: - Browser discovery & default management

enum BrowserService {
    // Probe URL used to ask Launch Services who handles the web.
    private static let probe = URL(string: "https://example.com")!

    /// All installed apps able to open https links, sorted by display name.
    static func installed() -> [Browser] {
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: probe)
        let browsers: [Browser] = urls.compactMap { url in
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else { return nil }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return Browser(url: url, name: name, bundleID: bundleID)
        }
        // Deduplicate by bundle id (Launch Services can list multiple copies).
        var seen = Set<String>()
        let unique = browsers.filter { seen.insert($0.bundleID).inserted }
        return unique.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The current default browser, if resolvable.
    static func current() -> Browser? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: probe),
              let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return Browser(url: url, name: name, bundleID: bundleID)
    }

    /// Sets the default handler for http + https. May trigger a one-time
    /// system confirmation dialog on modern macOS — that's Apple's, not ours.
    static func setDefault(_ browser: Browser, completion: @escaping (Error?) -> Void) {
        let ws = NSWorkspace.shared
        ws.setDefaultApplication(at: browser.url, toOpenURLsWithScheme: "https") { httpsErr in
            ws.setDefaultApplication(at: browser.url, toOpenURLsWithScheme: "http") { httpErr in
                DispatchQueue.main.async { completion(httpsErr ?? httpErr) }
            }
        }
    }
}

// MARK: - Menu bar controller

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var scrollMonitor: Any?
    private var scrollAccumulator: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self           // rebuilt lazily on open
        statusItem.menu = menu

        refreshIcon()
        installScrollHandler()

        // Keep the panel icon fresh if the default changes from elsewhere.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(refreshIcon),
            name: NSNotification.Name("com.apple.LaunchServices.applicationRegistered"),
            object: nil)
    }

    // MARK: Status icon

    @objc private func refreshIcon() {
        guard let button = statusItem.button else { return }
        if let current = BrowserService.current() {
            let icon = NSWorkspace.shared.icon(forFile: current.url.path)
            icon.size = NSSize(width: 18, height: 18)
            button.image = icon
            button.toolTip = "Default browser: \(current.name)\nScroll to switch · click for menu"
        } else {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Browser")
            button.toolTip = "No default browser detected"
        }
    }

    // MARK: Menu (built on demand)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = BrowserService.current()

        let header = NSMenuItem(title: "Default browser", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for browser in BrowserService.installed() {
            let item = NSMenuItem(title: browser.name,
                                  action: #selector(selectBrowser(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = browser
            item.state = (browser == current) ? .on : .off
            let icon = NSWorkspace.shared.icon(forFile: browser.url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func selectBrowser(_ sender: NSMenuItem) {
        guard let browser = sender.representedObject as? Browser else { return }
        apply(browser)
    }

    // MARK: Scroll-to-cycle

    private func installScrollHandler() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self,
                  let button = self.statusItem.button,
                  event.window == button.window else { return event }
            self.handleScroll(event.scrollingDeltaY)
            return nil
        }
    }

    private func handleScroll(_ deltaY: CGFloat) {
        scrollAccumulator += deltaY
        let threshold: CGFloat = 6     // one notch ≈ a few points; avoids over-triggering
        guard abs(scrollAccumulator) >= threshold else { return }
        let direction = scrollAccumulator > 0 ? -1 : 1   // scroll up → previous
        scrollAccumulator = 0
        cycle(by: direction)
    }

    private func cycle(by direction: Int) {
        let browsers = BrowserService.installed()
        guard browsers.count > 1 else { return }
        let current = BrowserService.current()
        let idx = browsers.firstIndex(where: { $0 == current }) ?? 0
        let next = ((idx + direction) % browsers.count + browsers.count) % browsers.count
        apply(browsers[next])
    }

    // MARK: Apply

    private func apply(_ browser: Browser) {
        BrowserService.setDefault(browser) { [weak self] error in
            self?.refreshIcon()
            if error == nil { self?.flash(browser.name) }
        }
    }

    /// Brief feedback in the menu bar so a scroll/click feels acknowledged.
    private func flash(_ name: String) {
        guard let button = statusItem.button else { return }
        let original = button.title
        button.title = " \(name)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            button.title = original
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon, menu bar only
app.run()
