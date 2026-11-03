import AppKit
import CPrivate
import ServiceManagement
import TouchyCore

// Only touched from the multitouch callback thread.
nonisolated(unsafe) private var gesture = EdgeGesture()
nonisolated(unsafe) private var levels = Levels()
// Main thread only; first touched from the main queue, so it's created there.
private let hud = HUD()

/// Called from the multitouch thread whenever a level is written.
func showLevel(_ control: EdgeControl, _ level: Float) {
    DispatchQueue.main.async { hud.show(control, level) }
}

private let onFrame: MTFrameCallback = { _, touches, count, _, _ in
    if TPTakeReset() {
        gesture = EdgeGesture()
        levels = Levels()
    }
    // An empty frame may come with a nil pointer; it still has to reach the gesture to end it.
    guard count >= 0, touches != nil || count == 0,
          let adjustment = gesture.update(UnsafeBufferPointer(start: touches, count: Int(count)))
    else { return }
    levels.apply(adjustment)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "Touchy")
        let menu = NSMenu()
        menu.delegate = self
        for item in [enabledItem, loginItem] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Touchy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        // Trackpad devices go stale across sleep, so re-attach on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(restart), name: NSWorkspace.didWakeNotification, object: nil)
        restart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        TPStop()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        enabledItem.state = enabled ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func restart() {
        TPStop()
        let running = enabled && TPStart(onFrame)
        statusItem.button?.appearsDisabled = !running
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        restart()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            try service.status == .enabled ? service.unregister() : service.register()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
