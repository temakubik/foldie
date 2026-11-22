import AppKit
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

/// Renders the sharpest, most recognizable icon for a menu bar item in either Color or Monochrome style.
struct MenuBarIconPreview: View {
    let item: MenuBarItem?
    var fallbackAppIcon: NSImage? = nil
    var iconStyle: IconStyle = .color
    var size: CGFloat = 16

    private var resolvedAppIcon: NSImage? {
        if let item, !item.isSystemItem, let icon = item.appIcon {
            return icon
        }
        return fallbackAppIcon
    }

    var body: some View {
        ZStack {
            if let appIcon = resolvedAppIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .saturation(iconStyle == .monochrome ? 0.0 : 1.0)
                    .contrast(iconStyle == .monochrome ? 1.12 : 1.0)
                    .opacity(iconStyle == .monochrome ? 0.88 : 1.0)
            } else if let captured = item?.capturedImage {
                Image(nsImage: captured)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.92, height: size * 0.92)
                    .saturation(iconStyle == .monochrome ? 0.0 : 1.0)
            } else {
                Image(systemName: item?.fallbackSymbolName ?? "app.fill")
                    .font(.system(size: size * 0.72, weight: .semibold))
                    .foregroundStyle(.primary.opacity(item == nil ? 0.55 : 0.88))
            }
        }
        .frame(width: size, height: size)
    }
}
