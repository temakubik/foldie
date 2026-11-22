import AppKit
import SwiftUI

/// Ultra-compact, shell-less floating list hugging right underneath Foldie's menu bar icon.
struct ListModeView: View {
    @ObservedObject var store: FoldieStore
    @State private var selectedIndex: Int = 0
    @State private var keyMonitor: Any?

    private struct FlatRow: Identifiable {
        let id: String
        let node: FoldieNode
        let depth: Int
        let parentFolderID: UUID?
    }

    private var flatRows: [FlatRow] {
        var rows: [FlatRow] = []
        func walk(_ nodes: [FoldieNode], depth: Int, parentID: UUID?) {
            for node in nodes {
                switch node {
                case .item(let key):
                    if store.isItemVisibleInUI(key: key) {
                        rows.append(FlatRow(id: node.id, node: node, depth: depth, parentFolderID: parentID))
                    }
                case .folder(let folder):
                    rows.append(FlatRow(id: node.id, node: node, depth: depth, parentFolderID: parentID))
                    if folder.isExpanded {
                        walk(folder.children, depth: depth + 1, parentID: folder.id)
                    }
                case .divider:
                    rows.append(FlatRow(id: node.id, node: node, depth: depth, parentFolderID: parentID))
                }
            }
        }
        walk(store.activeListNodes, depth: 0, parentID: store.swipedFolderID)
        return rows
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 3) {
                    if flatRows.isEmpty {
                        emptyFloatingPill
                    } else {
                        ForEach(Array(flatRows.enumerated()), id: \.element.id) { index, row in
                            rowView(for: row, index: index, isKeyboardSelected: index == selectedIndex)
                                .id(row.id)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedIndex) { _, newIdx in
                if flatRows.indices.contains(newIdx) {
                    withAnimation(.easeOut(duration: 0.14)) {
                        proxy.scrollTo(flatRows[newIdx].id, anchor: .center)
                    }
                }
            }
        }
        .background(Color.clear)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    @ViewBuilder
    private func rowView(for row: FlatRow, index: Int, isKeyboardSelected: Bool) -> some View {
        switch row.node {
        case .item(let key):
            FloatingItemPill(
                store: store,
                itemKey: key,
                nodeID: row.node.id,
                depth: row.depth,
                parentFolderID: row.parentFolderID,
                isHighlighted: isKeyboardSelected,
                onHoverSelect: { selectedIndex = index }
            )

        case .folder(let folder):
            FloatingFolderPill(
                store: store,
                folder: folder,
                depth: row.depth,
                isHighlighted: isKeyboardSelected,
                onHoverSelect: { selectedIndex = index }
            )

        case .divider(let divider):
            FloatingDividerPill(divider: divider, depth: row.depth)
        }
    }

    private var emptyFloatingPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Пусто • ПКМ → Настройки")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.20), radius: 5, y: 2)
        )
        .contextMenu {
            Button {
                store.onRequestClosePanel?()
                store.onRequestOpenOrganizer?()
            } label: {
                Label("Настройки Foldie...", systemImage: "gearshape")
            }
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let rows = flatRows
            guard !rows.isEmpty else { return event }

            switch event.keyCode {
            case 126: // Up arrow
                selectedIndex = max(0, selectedIndex - 1)
                return nil
            case 125: // Down arrow
                selectedIndex = min(rows.count - 1, selectedIndex + 1)
                return nil
            case 36, 49, 124: // Return, Space, Right
                guard rows.indices.contains(selectedIndex) else { return event }
                switch rows[selectedIndex].node {
                case .item(let key):
                    if event.keyCode != 124 {
                        store.activateItem(key: key, rightClick: false)
                    }
                case .folder(let folder):
                    withAnimation(.easeInOut(duration: 0.14)) {
                        store.toggleFolderExpanded(id: folder.id)
                    }
                case .divider:
                    break
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

// MARK: - Compact Floating Folder Pill

private struct FloatingFolderPill: View {
    @ObservedObject var store: FoldieStore
    let folder: FoldieFolder
    let depth: Int
    let isHighlighted: Bool
    let onHoverSelect: () -> Void

    @State private var isHovered = false

    private var active: Bool { isHovered || isHighlighted }
    private var isMono: Bool { store.config.preferences.iconStyle == .monochrome }
    private var tint: Color { isMono ? .primary : folder.accentColor }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 9)

            Image(systemName: folder.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isMono ? Color.primary.opacity(0.85) : folder.accentColor)
                .frame(width: 15, height: 15)

            Text(folder.name)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("\(store.countVisibleItems(in: folder))")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? tint.opacity(0.14) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            active ? tint.opacity(0.55) : Color.white.opacity(0.16),
                            lineWidth: active ? 1 : 0.65
                        )
                )
                .shadow(color: .black.opacity(active ? 0.24 : 0.14), radius: active ? 5 : 3, y: 1.5)
        )
        .padding(.leading, CGFloat(depth) * 10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.14)) {
                store.toggleFolderExpanded(id: folder.id)
            }
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering { onHoverSelect() }
        }
        .contextMenu {
            Button {
                store.onRequestClosePanel?()
                store.onRequestOpenOrganizer?()
            } label: {
                Label("Настройки Foldie...", systemImage: "gearshape")
            }
        }
    }
}

// MARK: - Compact Floating Divider

private struct FloatingDividerPill: View {
    let divider: FoldieDivider
    let depth: Int

    var body: some View {
        HStack(spacing: 4) {
            if !divider.label.isEmpty {
                Text(divider.label.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                    )
            } else {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 1)
        .padding(.leading, CGFloat(depth) * 10)
    }
}

// MARK: - Compact Floating App Pill

private struct FloatingItemPill: View {
    @ObservedObject var store: FoldieStore
    let itemKey: String
    let nodeID: String
    let depth: Int
    let parentFolderID: UUID?
    let isHighlighted: Bool
    let onHoverSelect: () -> Void

    @State private var isHovered = false

    private var active: Bool { isHovered || isHighlighted }

    private var liveItem: MenuBarItem? {
        store.liveItemsByKey[itemKey]
    }

    var body: some View {
        HStack(spacing: 7) {
            MenuBarIconPreview(
                item: liveItem,
                fallbackAppIcon: store.resolvedAppIcon(forItemKey: itemKey),
                iconStyle: store.config.preferences.iconStyle,
                size: 15
            )

            Text(store.displayName(forItemKey: itemKey))
                .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                .foregroundStyle(liveItem == nil ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? Color.accentColor.opacity(0.16) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            active ? Color.accentColor.opacity(0.60) : Color.white.opacity(0.15),
                            lineWidth: active ? 1 : 0.65
                        )
                )
                .shadow(color: .black.opacity(active ? 0.24 : 0.14), radius: active ? 5 : 3, y: 1.5)
        )
        .padding(.leading, CGFloat(depth) * 10)
        .contentShape(Rectangle())
        .onTapGesture {
            store.activateItem(key: itemKey, rightClick: false)
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering { onHoverSelect() }
        }
        .contextMenu {
            Button {
                store.activateItem(key: itemKey, rightClick: false)
            } label: {
                Label("Открыть", systemImage: "cursorarrow.click")
            }
            .disabled(liveItem == nil)

            Button {
                store.activateItem(key: itemKey, rightClick: true)
            } label: {
                Label("Правый клик", systemImage: "cursorarrow.click.2")
            }
            .disabled(liveItem == nil)

            let folders = store.allFolders()
            if !folders.isEmpty || parentFolderID != nil {
                Divider()
                Menu {
                    if parentFolderID != nil {
                        Button {
                            store.moveNode(nodeID: nodeID, toFolderID: nil)
                        } label: {
                            Label("В корень", systemImage: "tray")
                        }
                        if !folders.isEmpty { Divider() }
                    }
                    ForEach(folders) { folder in
                        if folder.id != parentFolderID {
                            Button {
                                store.moveNode(nodeID: nodeID, toFolderID: folder.id)
                            } label: {
                                Label(folder.name, systemImage: folder.symbolName)
                            }
                        }
                    }
                } label: {
                    Label("Переместить в папку", systemImage: "folder")
                }
            }

            Divider()

            Button {
                store.onRequestClosePanel?()
                store.onRequestOpenOrganizer?()
            } label: {
                Label("Настройки Foldie...", systemImage: "gearshape")
            }
        }
    }
}
