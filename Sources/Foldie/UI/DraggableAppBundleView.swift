import AppKit
import SwiftUI

/// Native AppKit drag source that puts Foldie.app's file URL onto the dragging pasteboard
/// identically to Finder, so macOS System Settings -> Privacy -> Accessibility accepts the drop reliably.
private final class DraggableBundleNSView: NSView, NSDraggingSource {
    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
        NSCursor.closedHand.push()
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
        mouseDownEvent = nil
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, let startEvent = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - startEvent.locationInWindow.x
        let dy = event.locationInWindow.y - startEvent.locationInWindow.y
        guard hypot(dx, dy) >= 3 else { return }

        didStartDrag = true
        NSCursor.pop()

        let appURL = Bundle.main.bundleURL
        let draggingItem = NSDraggingItem(pasteboardWriter: appURL as NSURL)

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 48, height: 48)

        let localPoint = convert(event.locationInWindow, from: nil)
        let dragRect = NSRect(x: localPoint.x - 24, y: localPoint.y - 24, width: 48, height: 48)
        draggingItem.setDraggingFrame(dragRect, contents: icon)

        let session = beginDraggingSession(with: [draggingItem], event: startEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        return context == .outsideApplication ? [.copy, .link] : .copy
    }
}

private struct NativeBundleDragOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableBundleNSView {
        let view = DraggableBundleNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: DraggableBundleNSView, context: Context) {}
}

/// Interactive draggable card allowing the user to drag Foldie.app directly into
/// macOS System Settings -> Privacy & Security -> Accessibility (or Screen Recording).
struct DraggableFoldieAppChip: View {
    var compact: Bool = false
    var onOpenSettings: (() -> Void)?

    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path)
    }

    private var appDisplayName: String {
        Bundle.main.bundleURL.lastPathComponent
    }

    var body: some View {
        HStack(spacing: compact ? 8 : 11) {
            // Draggable chip surface
            HStack(spacing: compact ? 7 : 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(appDisplayName)
                        .font(.system(size: compact ? 11.5 : 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(compact ? "Перетащите в Универсальный доступ" : "Потяните эту карточку прямо в окно «Универсальный доступ»")
                        .font(.system(size: compact ? 10 : 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Image(systemName: "hand.draw.fill")
                    .font(.system(size: compact ? 12 : 14))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, compact ? 9 : 11)
            .padding(.vertical, compact ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                Color.accentColor.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1.2, dash: [5, 3])
                            )
                    )
            )
            .overlay(NativeBundleDragOverlay())
            .help("Зажмите и перетащите Foldie.app прямо в список «Универсальный доступ» в Системных настройках")

            // Quick reveal in Finder button as backup
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: compact ? 11 : 12, weight: .medium))
                    .frame(width: compact ? 26 : 30, height: compact ? 26 : 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Показать Foldie.app в Finder")

            if let onOpenSettings {
                Button("Открыть") {
                    onOpenSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Открыть раздел «Универсальный доступ» в Системных настройках")
            }
        }
    }
}
