import AppKit
import SwiftUI

/// Ultra-compact, shell-less 3D rotating cylindrical drum anchored tightly under Foldie's menu bar icon.
/// Zero wasted top gap: the top item starts immediately beneath the status bar and curves smoothly on scroll.
struct CylinderMenuView: View {
    @ObservedObject var store: FoldieStore

    @State private var scrollOffset: Double = 0
    @State private var lastDetentIndex: Int = 0
    @State private var dragStartOffset: Double?
    @State private var scrollMonitor: Any?
    @State private var keyMonitor: Any?
    @State private var snapTask: Task<Void, Never>?

    private let cylinderRadius: CGFloat = 68
    private let angleStepDegrees: Double = 22.0
    private let cardWidth: CGFloat = 194
    private let cardHeight: CGFloat = 28

    private var nodes: [FoldieNode] {
        store.cylinderNodes
    }

    private var activeIndex: Int {
        guard !nodes.isEmpty else { return 0 }
        return min(max(Int(round(scrollOffset)), 0), nodes.count - 1)
    }

    /// Fixed top-aligned rotation axis right beneath Foldie's menu bar capsule so scrolling NEVER drops the active item downward!
    private let drumTopCenterY: CGFloat = 44.0

    var body: some View {
        VStack(spacing: 3) {
            if let currentFolder = store.currentCylinderFolder {
                HStack {
                    Button {
                        store.popCylinderFolder()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8.5, weight: .bold))
                            Image(systemName: currentFolder.symbolName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(store.config.preferences.iconStyle == .monochrome ? Color.primary.opacity(0.85) : currentFolder.accentColor)
                            Text(currentFolder.name)
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(.regularMaterial)
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
                                .shadow(color: .black.opacity(0.18), radius: 4, y: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 2)
            }

            if nodes.isEmpty {
                emptyDrumPill
            } else {
                drumStage
            }
        }
        .background(Color.clear)
        .onAppear {
            clampScrollOffset(animated: false)
            installEventMonitors()
        }
        .onDisappear {
            removeEventMonitors()
        }
        .onChange(of: nodes.count) { _, _ in
            clampScrollOffset(animated: true)
        }
        .onChange(of: store.cylinderFolderPath) { _, _ in
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                scrollOffset = 0
                lastDetentIndex = 0
            }
        }
        .onChange(of: store.swipedFolderID) { _, _ in
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                scrollOffset = 0
                lastDetentIndex = 0
            }
        }
        .onChange(of: store.activePopupFolderID) { _, _ in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                scrollOffset = 0
                lastDetentIndex = 0
            }
        }
    }

    // MARK: - Compact Top-Anchored 3D Drum Stage

    private var drumStage: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    let delta = Double(index) - scrollOffset
                    if delta >= -1.45 && delta <= 3.3 {
                        cylinderCard(for: node, at: index, delta: delta, centerX: geo.size.width / 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    snapTask?.cancel()
                    if dragStartOffset == nil {
                        dragStartOffset = scrollOffset
                    }
                    let base = dragStartOffset ?? scrollOffset
                    let deltaItems = -Double(value.translation.height) / 34.0
                    updateScrollOffset(base + deltaItems)
                }
                .onEnded { value in
                    let velocityDelta = -Double(value.predictedEndTranslation.height - value.translation.height) / 110.0
                    let target = clampedIndex(round(scrollOffset + velocityDelta))
                    dragStartOffset = nil
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                        scrollOffset = Double(target)
                    }
                    triggerDetentIfNeeded(for: target)
                }
        )
    }

    @ViewBuilder
    private func cylinderCard(for node: FoldieNode, at index: Int, delta: Double, centerX: CGFloat) -> some View {
        let angleDeg = delta * angleStepDegrees
        let rad = angleDeg * .pi / 180.0
        let cosVal = max(0.0, cos(rad))
        let yPos = drumTopCenterY + CGFloat(sin(rad)) * cylinderRadius
        let scale = CGFloat(0.78 + 0.22 * cosVal)
        let opacity = pow(cosVal, 1.55)
        let isCentered = abs(delta) < 0.45

        Button {
            if isCentered {
                activateNode(node)
            } else {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.80)) {
                    scrollOffset = Double(index)
                }
                triggerDetentIfNeeded(for: index)
            }
        } label: {
            cylinderCardContent(for: node, isCentered: isCentered)
        }
        .buttonStyle(.plain)
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCentered ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isCentered ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isCentered
                                ? Color.accentColor.opacity(0.65)
                                : Color.white.opacity(0.16),
                            lineWidth: isCentered ? 1.0 : 0.65
                        )
                )
        )
        .overlay {
            if case .item(let key) = node {
                RightClickOverlay {
                    store.activateItem(key: key, rightClick: true)
                }
            }
        }
        .shadow(
            color: Color.black.opacity(isCentered ? 0.26 : 0.12),
            radius: isCentered ? 6 : 3,
            y: isCentered ? 2 : 1
        )
        .scaleEffect(scale)
        .rotation3DEffect(
            .degrees(-angleDeg),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            anchorZ: 0,
            perspective: 0.46
        )
        .position(x: centerX, y: yPos)
        .opacity(opacity)
        .zIndex(100.0 - abs(delta) * 10.0)
    }

    @ViewBuilder
    private func cylinderCardContent(for node: FoldieNode, isCentered: Bool) -> some View {
        let isMono = store.config.preferences.iconStyle == .monochrome

        switch node {
        case .folder(let folder):
            HStack(spacing: 6) {
                Image(systemName: folder.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isMono ? Color.primary.opacity(0.85) : folder.accentColor)
                    .frame(width: 15, height: 15)

                Text(folder.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(store.countVisibleItems(in: folder))")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(isMono ? Color.primary.opacity(0.85) : folder.accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(isMono ? Color.primary.opacity(0.12) : folder.accentColor.opacity(0.20))
                            .overlay(
                                Capsule()
                                    .strokeBorder(isMono ? Color.primary.opacity(0.18) : folder.accentColor.opacity(0.45), lineWidth: 0.6)
                            )
                    )

                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle((isMono ? Color.secondary : folder.accentColor).opacity(isCentered ? 0.9 : 0.45))
            }
            .padding(.horizontal, 8)

        case .item(let key):
            let liveItem = store.liveItemsByKey[key]
            HStack(spacing: 7) {
                MenuBarIconPreview(
                    item: liveItem,
                    fallbackAppIcon: store.resolvedAppIcon(forItemKey: key),
                    iconStyle: store.config.preferences.iconStyle,
                    size: 15
                )

                Text(store.displayName(forItemKey: key))
                    .font(.system(size: 11.5, weight: isCentered ? .semibold : .medium))
                    .foregroundStyle(liveItem == nil ? .secondary : .primary)
                    .lineLimit(1)

                Spacer(minLength: 2)
            }
            .padding(.horizontal, 8)

        case .divider:
            EmptyView()
        }
    }

    private var emptyDrumPill: some View {
        VStack(spacing: 5) {
            Text(store.currentCylinderFolder != nil ? "Папка пуста" : "Нет приложений")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.20), radius: 5, y: 2)
        )
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contextMenu {
            Button {
                store.onRequestClosePanel?()
                store.onRequestOpenOrganizer?()
            } label: {
                Label("Настройки Foldie...", systemImage: "gearshape")
            }
        }
    }

    // MARK: - Interaction & Physics Helpers

    private func activateNode(_ node: FoldieNode) {
        switch node {
        case .item(let key):
            store.activateItem(key: key, rightClick: false)
        case .folder(let folder):
            store.enterCylinderFolder(folder)
        case .divider:
            break
        }
    }

    private func clampedIndex(_ value: Double) -> Int {
        guard !nodes.isEmpty else { return 0 }
        return min(max(Int(value), 0), nodes.count - 1)
    }

    private func clampScrollOffset(animated: Bool) {
        let maxIdx = Double(max(0, nodes.count - 1))
        let clamped = min(max(scrollOffset, 0), maxIdx)
        if animated {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                scrollOffset = clamped
            }
        } else {
            scrollOffset = clamped
        }
        lastDetentIndex = Int(round(clamped))
    }

    private func updateScrollOffset(_ rawTarget: Double) {
        let maxIdx = Double(max(0, nodes.count - 1))
        let clamped = min(max(rawTarget, 0), maxIdx)
        scrollOffset = clamped
        triggerDetentIfNeeded(for: Int(round(clamped)))
    }

    private func triggerDetentIfNeeded(for index: Int) {
        if index != lastDetentIndex {
            lastDetentIndex = index
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            store.sounds.playTick()
        }
    }

    private func scheduleSnap() {
        snapTask?.cancel()
        snapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let target = clampedIndex(round(scrollOffset))
            withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
                scrollOffset = Double(target)
            }
            triggerDetentIfNeeded(for: target)
        }
    }

    private func stepBy(_ delta: Int) {
        guard !nodes.isEmpty else { return }
        let target = clampedIndex(Double(activeIndex + delta))
        withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
            scrollOffset = Double(target)
        }
        triggerDetentIfNeeded(for: target)
    }

    private func installEventMonitors() {
        removeEventMonitors()

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Horizontal swipe (trackpad, horizontal mouse wheel, or Shift+wheel) switches active folder cleanly
            if store.hider.effectiveHorizontalScrollDelta(for: event) != nil {
                store.hider.processHorizontalScrollEvent(event)
                return nil
            }
            guard !nodes.isEmpty else { return event }
            let deltaY: Double = event.hasPreciseScrollingDeltas
                ? -Double(event.scrollingDeltaY) / 36.0
                : -Double(event.scrollingDeltaY) * 0.45
            if abs(deltaY) > 0.001 {
                updateScrollOffset(scrollOffset + deltaY)
                scheduleSnap()
            }
            return nil
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 126: // Up arrow
                stepBy(-1)
                return nil
            case 125: // Down arrow
                stepBy(1)
                return nil
            case 36, 49, 124: // Return, Space, Right
                if !nodes.isEmpty {
                    let current = nodes[activeIndex]
                    if event.keyCode == 124 {
                        if case .folder(let folder) = current {
                            store.enterCylinderFolder(folder)
                        }
                    } else {
                        activateNode(current)
                    }
                }
                return nil
            case 123, 51: // Left, Delete
                if !store.cylinderFolderPath.isEmpty {
                    store.popCylinderFolder()
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    private func removeEventMonitors() {
        snapTask?.cancel()
        snapTask = nil
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
