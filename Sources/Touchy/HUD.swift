import AppKit
import TouchyCore

/// Level overlay in the top-right corner, where macOS shows its own. The window only exists
/// while it's visible and is freed after fading out, so it costs nothing when idle.
final class HUD: NSObject {
    private static let size = NSSize(width: 220, height: 44)
    private var panel: NSPanel?
    private var generation = 0
    private var iconKey = -1
    private let icon = NSImageView(frame: NSRect(x: 14, y: 12, width: 20, height: 20))
    private let track = CALayer()
    private let fill = CALayer()

    func show(_ control: EdgeControl, _ level: Float) {
        generation += 1
        let panel = self.panel ?? makePanel()
        // Follow the screen under the cursor, even if the panel is already up on another one.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let origin = NSPoint(x: frame.maxX - Self.size.width - 12, y: frame.maxY - Self.size.height - 12)
            if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        }
        if self.panel == nil {
            panel.orderFrontRegardless()
            self.panel = panel
        } else if panel.alphaValue < 1 {
            panel.animator().alphaValue = 1 // cancels a fade in progress
        }
        setIcon(control, level)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame.size.width = track.bounds.width * CGFloat(level)
        CATransaction.commit()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(fadeOut), object: nil)
        perform(#selector(fadeOut), with: nil, afterDelay: 1.2)
    }

    @objc private func fadeOut() {
        guard let panel else { return }
        let shown = generation
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) { [weak self] in
            guard let self, self.generation == shown else { return }
            panel.orderOut(nil)
            self.panel = nil
        }
    }

    /// Only swaps the symbol when it would look different, not on every level change.
    private func setIcon(_ control: EdgeControl, _ level: Float) {
        let key = control == .brightness ? (level < 0.5 ? 0 : 1) : 2 + Int((level * 3).rounded(.up))
        guard key != iconKey else { return }
        iconKey = key
        icon.image = switch key {
        case 0: NSImage(systemSymbolName: "sun.min.fill", accessibilityDescription: "Brightness")
        case 1: NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness")
        case 2: NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: "Volume")
        default: NSImage(systemSymbolName: "speaker.wave.3.fill", variableValue: Double(key - 2) / 3,
                         accessibilityDescription: "Volume")
        }
    }

    private func makePanel() -> NSPanel {
        let size = Self.size
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        icon.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        icon.contentTintColor = .labelColor
        content.addSubview(icon)

        let bar = NSView(frame: NSRect(x: 46, y: 19, width: size.width - 64, height: 6))
        bar.wantsLayer = true
        track.frame = bar.bounds
        track.cornerRadius = 3
        track.masksToBounds = true
        fill.frame = bar.bounds
        // Resolve colors per panel so light/dark mode changes are picked up on the next show.
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            track.backgroundColor = NSColor.labelColor.withAlphaComponent(0.2).cgColor
            fill.backgroundColor = NSColor.labelColor.cgColor
        }
        track.addSublayer(fill)
        bar.layer?.addSublayer(track)
        content.addSubview(bar)

        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: content.frame)
            glass.cornerRadius = size.height / 2
            glass.contentView = content
            panel.contentView = glass
        } else {
            let blur = NSVisualEffectView(frame: content.frame)
            blur.material = .hudWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = size.height / 2
            blur.layer?.masksToBounds = true
            blur.addSubview(content)
            panel.contentView = blur
        }
        return panel
    }
}
