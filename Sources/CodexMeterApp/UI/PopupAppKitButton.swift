#if os(macOS)
import AppKit
import SwiftUI

struct PopupAppKitButton: NSViewRepresentable {
    enum Tone {
        case primary
        case secondary
    }

    let title: String
    let systemImage: String?
    let tone: Tone
    let minimumWidth: CGFloat
    let accessibilityIdentifier: String?
    let isEnabled: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> PopupAppKitButtonControl {
        let control = PopupAppKitButtonControl()
        update(control)
        return control
    }

    func updateNSView(_ control: PopupAppKitButtonControl, context: Context) {
        update(control)
    }

    private func update(_ control: PopupAppKitButtonControl) {
        control.controlTitle = title
        control.systemImage = systemImage
        control.tone = tone
        control.minimumWidth = minimumWidth
        control.isEnabled = isEnabled
        control.actionHandler = action
        control.setAccessibilityLabel(title)
        control.setAccessibilityIdentifier(accessibilityIdentifier)
        control.invalidateIntrinsicContentSize()
        control.needsDisplay = true
    }
}

final class PopupAppKitButtonControl: NSControl {
    var controlTitle = ""
    var systemImage: String?
    var tone = PopupAppKitButton.Tone.secondary
    var minimumWidth: CGFloat = 76
    var actionHandler: (() -> Void)?

    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    override var acceptsFirstResponder: Bool { false }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: minimumWidth, height: GlassTokens.pillHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        needsDisplay = true
        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: .infinity,
            mode: .eventTracking
        ) { [weak self] nextEvent, stop in
            guard let self else {
                stop.pointee = true
                return
            }
            if nextEvent?.type == .leftMouseUp {
                self.isPressed = false
                self.needsDisplay = true
                stop.pointee = true
                if let nextEvent, self.bounds.contains(self.convert(nextEvent.locationInWindow, from: nil)) {
                    self.actionHandler?()
                }
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: GlassTokens.pillRadius, yRadius: GlassTokens.pillRadius)
        backgroundColor.setFill()
        path.fill()

        if tone == .secondary {
            NSColor.separatorColor.withAlphaComponent(0.58).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        drawContent()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        actionHandler?()
        return true
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    private var backgroundColor: NSColor {
        let opacity: CGFloat = isEnabled ? (isPressed ? 0.72 : (isHovered ? 0.88 : 1)) : 0.52
        switch tone {
        case .primary:
            return NSColor(calibratedRed: 0.10, green: 0.14, blue: 1.0, alpha: opacity)
        case .secondary:
            return NSColor.controlBackgroundColor.withAlphaComponent(opacity)
        }
    }

    private var foregroundColor: NSColor {
        let color: NSColor = tone == .primary ? .white : .labelColor
        return isEnabled ? color : color.withAlphaComponent(0.52)
    }

    private func drawContent() {
        let font = NSFont.systemFont(ofSize: GlassTokens.popupMetaFontSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraph,
        ]
        let attributedTitle = NSAttributedString(string: controlTitle, attributes: attributes)
        let titleSize = attributedTitle.size()
        let iconSize = NSSize(width: 12, height: 12)
        let spacing: CGFloat = systemImage == nil ? 0 : 6
        let contentWidth = titleSize.width + spacing + (systemImage == nil ? 0 : iconSize.width)
        var cursorX = floor((bounds.width - contentWidth) / 2)

        if let systemImage,
           let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
            let configured = image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            ) ?? image
            configured.isTemplate = true
            foregroundColor.set()
            let iconRect = NSRect(
                x: cursorX,
                y: floor((bounds.height - iconSize.height) / 2),
                width: iconSize.width,
                height: iconSize.height
            )
            configured.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
            cursorX += iconSize.width + spacing
        }

        attributedTitle.draw(
            in: NSRect(
                x: cursorX,
                y: floor((bounds.height - titleSize.height) / 2),
                width: ceil(titleSize.width),
                height: ceil(titleSize.height)
            )
        )
    }
}
#endif
