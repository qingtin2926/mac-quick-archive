import Cocoa

final class HUDPanelController {

    static let shared = HUDPanelController()

    private var panel: NSPanel?
    private var spinner: NSProgressIndicator?
    private var statusIconView: NSImageView?
    private var titleLabel: NSTextField?
    private var subtitleLabel: NSTextField?
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    func showProgress(title: String, subtitle: String) {
        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.ensurePanelCreated()

            self.statusIconView?.isHidden = true
            self.spinner?.isHidden = false
            self.spinner?.startAnimation(nil)
            self.titleLabel?.stringValue = title
            self.subtitleLabel?.stringValue = subtitle

            self.positionAtTopRight()
            self.panel?.alphaValue = 1.0
            self.panel?.orderFrontRegardless()
        }
    }

    func showSuccess(title: String, subtitle: String, autoHideAfter delay: TimeInterval = 1.2) {
        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.ensurePanelCreated()

            self.spinner?.stopAnimation(nil)
            self.spinner?.isHidden = true

            if let iconView = self.statusIconView {
                let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
                let img = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
                iconView.image = img
                iconView.contentTintColor = NSColor.systemGreen
                iconView.isHidden = false
            }

            self.titleLabel?.stringValue = title
            self.subtitleLabel?.stringValue = subtitle

            self.positionAtTopRight()
            self.panel?.alphaValue = 1.0
            self.panel?.orderFrontRegardless()

            let work = DispatchWorkItem { [weak self = self] in
                guard let self = self, let panel = self.panel else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.28
                    panel.animator().alphaValue = 0.0
                }, completionHandler: {
                    panel.orderOut(nil)
                })
            }
            self.hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func hideImmediately() {
        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.spinner?.stopAnimation(nil)
            self.panel?.orderOut(nil)
        }
    }

    private func ensurePanelCreated() {
        guard panel == nil else { return }

        let width: CGFloat = 310
        let height: CGFloat = 64
        let rect = NSRect(x: 0, y: 0, width: width, height: height)

        let p = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let visualEffect = NSVisualEffectView(frame: rect)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 14
        visualEffect.layer?.masksToBounds = true

        let ind = NSProgressIndicator(frame: NSRect(x: 18, y: 20, width: 24, height: 24))
        ind.style = .spinning
        ind.controlSize = .regular
        ind.isDisplayedWhenStopped = false
        visualEffect.addSubview(ind)

        let icon = NSImageView(frame: NSRect(x: 16, y: 18, width: 28, height: 28))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.isHidden = true
        visualEffect.addSubview(icon)

        let tLabel = NSTextField(labelWithString: "")
        tLabel.frame = NSRect(x: 54, y: 33, width: width - 68, height: 20)
        tLabel.font = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
        tLabel.textColor = .labelColor
        tLabel.lineBreakMode = .byTruncatingTail
        visualEffect.addSubview(tLabel)

        let sLabel = NSTextField(labelWithString: "")
        sLabel.frame = NSRect(x: 54, y: 13, width: width - 68, height: 17)
        sLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        sLabel.textColor = .secondaryLabelColor
        sLabel.lineBreakMode = .byTruncatingMiddle
        visualEffect.addSubview(sLabel)

        p.contentView = visualEffect

        self.panel = p
        self.spinner = ind
        self.statusIconView = icon
        self.titleLabel = tLabel
        self.subtitleLabel = sLabel
    }

    private func positionAtTopRight() {
        guard let panel = panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let x = visible.maxX - panel.frame.width - 20
        let y = visible.maxY - panel.frame.height - 16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
