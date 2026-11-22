import AppKit
import QuartzCore

/// Pixel-perfect fixed-width capsule view placed inside NSStatusBarButton.
/// Wraps [Icon | Clipped/Marquee Title | Inner Count Pill] inside one unified Liquid-Glass outer capsule.
@MainActor
final class StatusBarFolderView: NSView {
    enum LayoutStyle {
        /// Fixed 122pt outer capsule: ( [Icon] [Clipped/Marquee Title] (Count) )
        case mainFixedWidth
        /// Fixed 50pt compact pinned folder capsule: ( [Icon] (Count) )
        case pinnedCompact
    }

    private let layoutStyle: LayoutStyle
    private let outerCapsule = NSView()
    private let iconView = NSImageView()
    private let textClipView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeContainer = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")

    private var marqueeTimer: Timer?
    private var marqueeOffset: CGFloat = 0
    private var marqueeDirection: CGFloat = -1
    private var marqueePauseTicks: Int = 0
    private var textOverflow: CGFloat = 0
    private var isCurrentlyHovered: Bool = false

    private var currentAccentColor: NSColor?
    private var currentIconStyle: IconStyle = .color
    private var currentCapsuleShape: CapsuleShapeStyle = .rounded
    private var currentCount: Int = 0

    static let mainFixedWidth: CGFloat = 122
    static let pinnedFixedWidth: CGFloat = 52

    init(style: LayoutStyle) {
        self.layoutStyle = style
        let width: CGFloat = style == .mainFixedWidth ? Self.mainFixedWidth : Self.pinnedFixedWidth
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 26))
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyCapsuleColors()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        clipsToBounds = false

        outerCapsule.wantsLayer = true
        outerCapsule.layer?.masksToBounds = true
        outerCapsule.layer?.cornerCurve = .continuous
        addSubview(outerCapsule)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
        outerCapsule.addSubview(iconView)

        if layoutStyle == .mainFixedWidth {
            textClipView.wantsLayer = true
            textClipView.layer?.masksToBounds = true
            outerCapsule.addSubview(textClipView)

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
        badgeContainer.layer?.cornerRadius = 8.0
        badgeContainer.layer?.masksToBounds = true
        outerCapsule.addSubview(badgeContainer)

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
        iconStyle: IconStyle,
        capsuleShape: CapsuleShapeStyle = .rounded
    ) {
        currentAccentColor = accentColor
        currentIconStyle = iconStyle
        currentCapsuleShape = capsuleShape
        currentCount = count

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

        // 3. Configure inner count pill (always visible in mainFixedWidth so the capsule stays balanced even at 0)
        if layoutStyle == .mainFixedWidth || count > 0 {
            badgeContainer.isHidden = false
            badgeLabel.stringValue = count > 99 ? "99+" : "\(count)"
        } else {
            badgeContainer.isHidden = true
        }

        applyCapsuleColors()
        layoutSubviewsFrames()
    }

    private func applyCapsuleColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            // Outer Foldie capsule (subtle translucent glass pill around icon + title + count badge)
            let hoverBoost: CGFloat = isCurrentlyHovered ? 0.08 : 0.0
            if currentIconStyle == .color, let accent = currentAccentColor {
                outerCapsule.layer?.backgroundColor = accent.withAlphaComponent(0.13 + hoverBoost).cgColor
                outerCapsule.layer?.borderColor = accent.withAlphaComponent(isCurrentlyHovered ? 0.48 : 0.30).cgColor
                outerCapsule.layer?.borderWidth = 0.75
            } else {
                outerCapsule.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.09 + hoverBoost).cgColor
                outerCapsule.layer?.borderColor = NSColor.labelColor.withAlphaComponent(isCurrentlyHovered ? 0.30 : 0.18).cgColor
                outerCapsule.layer?.borderWidth = 0.75
            }

            // Inner count pill badge (always crisp; softly muted at 0 so the capsule never looks empty)
            if currentCount > 0 {
                badgeLabel.textColor = .labelColor
                if currentIconStyle == .color, let accent = currentAccentColor {
                    badgeContainer.layer?.backgroundColor = accent.withAlphaComponent(0.32).cgColor
                    badgeContainer.layer?.borderColor = accent.withAlphaComponent(0.60).cgColor
                    badgeContainer.layer?.borderWidth = 0.75
                } else {
                    badgeContainer.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.18).cgColor
                    badgeContainer.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.28).cgColor
                    badgeContainer.layer?.borderWidth = 0.65
                }
            } else {
                badgeLabel.textColor = .secondaryLabelColor
                badgeContainer.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
                badgeContainer.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
                badgeContainer.layer?.borderWidth = 0.6
            }
        }
    }

    private func layoutSubviewsFrames() {
        // Match macOS 26 system indicator height (~24pt) inside the menu bar instead of shrinking to 19pt
        let capsuleH: CGFloat = max(24, bounds.height)
        let capsuleY: CGFloat = floor((bounds.height - capsuleH) / 2)
        outerCapsule.frame = NSRect(x: 1, y: capsuleY, width: max(22, bounds.width - 2), height: capsuleH)
        outerCapsule.layer?.cornerRadius = currentCapsuleShape.cornerRadius(forHeight: capsuleH)
        outerCapsule.layer?.cornerCurve = .continuous

        let cw = outerCapsule.bounds.width
        let ch = outerCapsule.bounds.height
        let iconSize: CGFloat = 15
        let iconY = floor((ch - iconSize) / 2)

        switch layoutStyle {
        case .mainFixedWidth:
            // Inside 120pt capsule: [ 8px | 15px icon | 5px | ~60px title clip | 5px | 22px count pill | 5px ]
            iconView.frame = NSRect(x: 8, y: iconY, width: iconSize, height: iconSize)

            let badgeH: CGFloat = 16
            let badgeW: CGFloat = badgeLabel.stringValue.count >= 3 ? 26 : 21
            let badgeX = cw - badgeW - 5
            let badgeY = floor((ch - badgeH) / 2)
            badgeContainer.frame = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
            badgeContainer.layer?.cornerRadius = currentCapsuleShape == .capsule ? (badgeH / 2.0) : 4.5
            badgeContainer.layer?.cornerCurve = .continuous
            badgeLabel.sizeToFit()
            let bTextH = ceil(badgeLabel.frame.height)
            let bTextY = floor((badgeH - bTextH) / 2.0)
            badgeLabel.frame = NSRect(x: 0, y: bTextY, width: badgeW, height: bTextH)

            let titleX: CGFloat = 28
            let rightEdge = badgeContainer.isHidden ? (cw - 8) : (badgeX - 5)
            let clipW = max(16, rightEdge - titleX)
            textClipView.frame = NSRect(x: titleX, y: floor((ch - 17) / 2), width: clipW, height: 17)

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
            // Inside 52pt capsule: [ 7px | 15px icon | 4px | 21px count pill | 5px ]
            let badgeH: CGFloat = 16
            let badgeW: CGFloat = badgeLabel.stringValue.count >= 3 ? 25 : 21
            if badgeContainer.isHidden {
                iconView.frame = NSRect(x: floor((cw - iconSize) / 2), y: iconY, width: iconSize, height: iconSize)
            } else {
                iconView.frame = NSRect(x: 7, y: iconY, width: iconSize, height: iconSize)
                let badgeY = floor((ch - badgeH) / 2)
                badgeContainer.frame = NSRect(x: cw - badgeW - 5, y: badgeY, width: badgeW, height: badgeH)
                badgeContainer.layer?.cornerRadius = currentCapsuleShape == .capsule ? (badgeH / 2.0) : 4.5
                badgeContainer.layer?.cornerCurve = .continuous
                badgeLabel.sizeToFit()
                let bTextH = ceil(badgeLabel.frame.height)
                let bTextY = floor((badgeH - bTextH) / 2.0)
                badgeLabel.frame = NSRect(x: 0, y: bTextY, width: badgeW, height: bTextH)
            }
        }
    }

    // MARK: - Smooth Hover Marquee Scrolling

    func setHovering(_ hovering: Bool) {
        isCurrentlyHovered = hovering
        applyCapsuleColors()
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
        marqueePauseTicks = 10
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

        let speed: CGFloat = 1.15
        let minX = -(textOverflow + 4)

        marqueeOffset += marqueeDirection * speed
        if marqueeOffset <= minX {
            marqueeOffset = minX
            marqueeDirection = 1
            marqueePauseTicks = 24
        } else if marqueeOffset >= 0 {
            marqueeOffset = 0
            marqueeDirection = -1
            marqueePauseTicks = 24
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
