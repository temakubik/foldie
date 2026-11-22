import SwiftUI

/// Shell-less, frameless container rendering ONLY the floating menu items (List or 3D Cylinder).
/// Settings are accessed via right-click on Foldie's menu bar icon (or right-click on any item).
struct FoldiePopoverView: View {
    @ObservedObject var store: FoldieStore

    var body: some View {
        Group {
            switch store.config.preferences.displayMode {
            case .list:
                ListModeView(store: store)
            case .cylinder:
                CylinderMenuView(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }
}
