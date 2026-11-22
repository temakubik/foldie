import AppKit
import QuartzCore

/// Pixel-perfect fixed-width custom view placed inside NSStatusBarButton.
/// Features:
/// - Fixed total width so the menu bar NEVER jumps when switching folders.
/// - Clean spacing between icon, title, and count pill (zero overlap).
/// - Clipped title container that smoothly marquee-scrolls on hover when text overflows.
/// - Distinct tinted pill badge for the item count so numbers never look like part of the name.
@MainActor
final class StatusBarFolderView: NSView {
    enum LayoutStyle {
        /// Fixed 116pt capsule: [Icon] [Clipped/Marquee Title] [Count Pill]
        case mainFixedWidth
        /// Fixed 48pt compact pinned folder: [Icon] [Count Pill]
        case pinnedCompact
    }

    private let layoutStyle: LayoutStyle
    private let iconView = NSImageView()
    private let textClipView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeContainer = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")

    private var marqueeTimer: Timer?
    private var marqueeOffset: CGFloat = 0
    private var marqueeDirection: CGFloat = -1 // -1 scrolling left, +1 scrolling back right
    private var marqueePauseTicks: Int = 0
    private var textOverflow: CGFloat = 0
    private var isCurrentlyHovered: Bool = false

    static let mainFixedWidth: CGFloat = 116
    static let pinnedFixedWidth: CGFloat = 48

    init(style: LayoutStyle) {
        self.layoutStyle = style
        let width: CGFloat = style == .mainFixedWidth ? Self.mainFixedWidth : Self.pinnedFixedWidth
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let clicks pass straight through to NSStatusBarButton
        return nil
    }

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
        addSubview(iconView)

        if layoutStyle == .mainFixedWidth {
            textClipView.wantsLayer = true
            textClipView.layer?.masksToBounds = true
            addSubview(textClipView)

            titleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
            titleLabel.textColor = .labelColor
            titleLabel.lineBreakMode = .byClipping
            titleLabel.maximumNumberOfLines = 1
            titleLabel.isBezeled = false
            titleLabel.drawsBackground = false
            titleLabel.isEditable = false
            titleLabel.isSelectable = false
            textClipView.addSubview(titleLabel)
        }

        badgeContainer.wantsLayer = true
        badgeContainer.layer?.cornerRadius = 7.0
        badgeContainer.layer?.masksToBounds = true
        addSubview(badgeContainer)

        badgeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)
        badgeLabel.textColor = .labelColor
        badgeLabel.alignment = .center
        badgeLabel.maximumNumberOfLines = 1
        badgeLabel.isBezeled = false
        badgeLabel.drawsBackground = false
        badgeLabel.isEditable = false
        badgeLabel.isSelectable = false
        badgeContainer.addSubview(badgeLabel)
    }

    override func layout() {
        super.layout()
        layoutSubviewsFrames()
    }

    func configure(
        symbolName: String,
        title: String,
        count: Int,
        accentColor: NSColor?,
        iconStyle: IconStyle
    ) {
        // 1. Configure icon (colored palette or native monochrome template)
        let baseConfig = NSImage.SymbolConfiguration(pointSize: 13.0, weight: .semibold)
        if iconStyle == .color, let accentColor {
            let paletteConfig = baseConfig.applying(.init(paletteColors: [accentColor]))
            let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
                .withSymbolConfiguration(paletteConfig)
            img?.isTemplate = false
            iconView.image = img
        } else {
            let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
                .withSymbolConfiguration(baseConfig)
            img?.isTemplate = true
            iconView.image = img
        }

        // 2. Configure title (main fixed-width mode)
        if layoutStyle == .mainFixedWidth {
            let oldTitle = titleLabel.stringValue
            titleLabel.stringValue = title
            titleLabel.sizeToFit()
            if oldTitle != title {
                resetMarqueePosition()
            }
        }

        // 3. Configure distinct count pill badge
        if count > 0 {
            badgeContainer.isHidden = false
            badgeLabel.stringValue = count > 99 ? "99+" : "\(count)"
            if iconStyle == .color, let accentColor {
                badgeContainer.layer?.backgroundColor = accentColor.withAlphaComponent(0.28).cgColor
                badgeContainer.layer?.borderColor = accentColor.withAlphaComponent(0.55).cgColor
                badgeContainer.layer?.borderWidth = 0.75
            } else {
                badgeContainer.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
                badgeContainer.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.26).cgColor
                badgeContainer.layer?.borderWidth = 0.75
            }
        } else {
            badgeContainer.isHidden = true
        }

        layoutSubviewsFrames()
    }

    private func layoutSubviewsFrames() {
        let h = bounds.height
        let centerY = floor((h - 16) / 2)

        switch layoutStyle {
        case .mainFixedWidth:
            // [ 6px | 16px icon | 5px | 58px title clip | 5px | 22px count pill | 4px ] = 116px
            iconView.frame = NSRect(x: 6, y: centerY, width: 16, height: 16)

            let badgeWidth: CGFloat = badgeLabel.stringValue.count >= 3 ? 25 : 21
            let badgeX = bounds.width - badgeWidth - 4
            let badgeY = floor((h - 14) / 2)
            badgeContainer.frame = NSRect(x: badgeX, y: badgeY, width: badgeWidth, height: 14)
            badgeLabel.frame = NSRect(x: 0, y: 0.5, width: badgeWidth, height: 13)

            let titleX: CGFloat = 27
            let rightEdge = badgeContainer.isHidden ? (bounds.width - 6) : (badgeX - 5)
            let clipW = max(16, rightEdge - titleX)
            textClipView.frame = NSRect(x: titleX, y: floor((h - 16) / 2), width: clipW, height: 16)

            titleLabel.sizeToFit()
            let labelW = ceil(titleLabel.frame.width)
            let labelH = ceil(titleLabel.frame.height)
            let labelY = floor((textClipView.bounds.height - labelH) / 2) + 0.5
            textOverflow = max(0, labelW - clipW)

            if textOverflow <= 1 {
                marqueeOffset = 0
                stopMarqueeTimer()
            }
            titleLabel.frame = NSRect(x: marqueeOffset, y: labelY, width: labelW, height: labelH)

        case .pinnedCompact:
            // [ 5px | 16px icon | 4px | 20px count pill | 3px ] = 48px
            let badgeWidth: CGFloat = badgeLabel.stringValue.count >= 3 ? 23 : 20
            if badgeContainer.isHidden {
                iconView.frame = NSRect(x: floor((bounds.width - 16) / 2), y: centerY, width: 16, height: 16)
            } else {
                iconView.frame = NSRect(x: 5, y: centerY, width: 16, height: 16)
                let badgeY = floor((h - 14) / 2)
                badgeContainer.frame = NSRect(x: 24, y: badgeY, width: badgeWidth, height: 14)
                badgeLabel.frame = NSRect(x: 0, y: 0.5, width: badgeWidth, height: 13)
            }
        }
    }

    // MARK: - Smooth Hover Marquee Scrolling

    func setHovering(_ hovering: Bool) {
        isCurrentlyHovered = hovering
        guard layoutStyle == .mainFixedWidth else { return }

        if hovering && textOverflow > 1 {
            startMarqueeTimer()
        } else {
            stopMarqueeTimer()
            animateResetToStart()
        }
    }

    private func startMarqueeTimer() {
        stopMarqueeTimer()
        marqueePauseTicks = 10 // brief natural pause before scrolling starts (~0.3s)
        marqueeDirection = -1

        marqueeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickMarquee()
            }
        }
    }

    private func stopMarqueeTimer() {
        marqueeTimer?.invalidate()
        marqueeTimer = nil
    }

    private func tickMarquee() {
        guard isCurrentlyHovered, textOverflow > 1 else {
            stopMarqueeTimer()
            return
        }

        if marqueePauseTicks > 0 {
            marqueePauseTicks -= 1
            return
        }

        let speed: CGFloat = 1.15 // ~35 pt/sec smooth glide
        let minX = -(textOverflow + 4)

        marqueeOffset += marqueeDirection * speed
        if marqueeOffset <= minX {
            marqueeOffset = minX
            marqueeDirection = 1
            marqueePauseTicks = 24 // pause at the end (~0.8s)
        } else if marqueeOffset >= 0 {
            marqueeOffset = 0
            marqueeDirection = -1
            marqueePauseTicks = 24 // pause at the start (~0.8s)
        }

        var frame = titleLabel.frame
        frame.origin.x = marqueeOffset
        titleLabel.frame = frame
    }

    private func resetMarqueePosition() {
        stopMarqueeTimer()
        marqueeOffset = 0
        marqueeDirection = -1
        var frame = titleLabel.frame
        frame.origin.x = 0
        titleLabel.frame = frame
        if isCurrentlyHovered && textOverflow > 1 {
            startMarqueeTimer()
        }
    }

    private func animateResetToStart() {
        marqueeOffset = 0
        marqueeDirection = -1
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            var frame = titleLabel.frame
            frame.origin.x = 0
            titleLabel.animator().frame = frame
        }
    }
}
