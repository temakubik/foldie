import AppKit
import SwiftUI

enum OrganizerTab: String, CaseIterable, Identifiable {
    case organize = "organize"
    case appearance = "appearance"
    case permissions = "permissions"
    case help = "help"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .organize: return "Сортировка и папки"
        case .appearance: return "Поведение и вид"
        case .permissions: return "Разрешения"
        case .help: return "Справка"
        }
    }

    var symbolName: String {
        switch self {
        case .organize: return "folder.fill"
        case .appearance: return "slider.horizontal.3"
        case .permissions: return "checkmark.shield.fill"
        case .help: return "questionmark.circle.fill"
        }
    }
}

enum SidebarFilter: Hashable {
    case all
    case rootOnly
    case folder(UUID)
}

struct OrganizerWindowView: View {
    @ObservedObject var store: FoldieStore
    let onOpenMenuBarPopover: () -> Void

    @State private var selectedTab: OrganizerTab = .organize
    @State private var sidebarFilter: SidebarFilter = .all
    @State private var localSearch: String = ""
    @State private var targetedSidebarFilter: SidebarFilter?

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow, state: .active)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                if store.hider.conflictingAppName != nil || !store.hider.isFolderVisibleOnscreen {
                    menuBarVisibilityBanner
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }

                Divider().opacity(0.45)

                Group {
                    switch selectedTab {
                    case .organize:
                        organizeTabContent
                    case .appearance:
                        appearanceTabContent
                    case .permissions:
                        permissionsTabContent
                    case .help:
                        HelpGuideView(store: store) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTab = .permissions
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let folderState = store.folderEditorState {
                FolderEditorOverlay(
                    state: folderState,
                    onCancel: { store.folderEditorState = nil },
                    onSave: { store.commitFolderEditor($0) }
                )
            }

            if let dividerState = store.dividerEditorState {
                DividerEditorOverlay(
                    state: dividerState,
                    onCancel: { store.dividerEditorState = nil },
                    onSave: { store.commitDividerEditor($0) }
                )
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            store.refreshItems(captureThumbnails: false)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#248FFF") ?? .blue, Color(hex: "#4648E8") ?? .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: store.config.preferences.statusIconSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Foldie")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text("Иконок: \(store.visibleLiveItemCount)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .fixedSize()

            // Full-width single-line tab bar
            HStack(spacing: 3) {
                ForEach(OrganizerTab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.symbolName)
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var menuBarVisibilityBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                if let conflictName = store.hider.conflictingAppName {
                    Text("Иконку Foldie в строке меню скрывает «\(conflictName)»")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Сейчас запущен \(conflictName) — он прячет все новые иконки (включая Foldie) за левый край экрана. Закройте его, чтобы Foldie появился в строке меню.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Иконка Foldie скрыта за вырезом экрана или в «Разрешить в строке меню»")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Убедитесь, что Foldie включён в настройках «Строка меню» macOS, или нажмите «Показать в меню».")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 6)

            if let conflictName = store.hider.conflictingAppName {
                Button("Закрыть \(conflictName) и показать Foldie") {
                    store.hider.quitConflictingManagerAndReveal()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button("Строка меню macOS") {
                    store.permissions.openMenuBarSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Показать в меню") {
                    store.hider.quitConflictingManagerAndReveal()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.orange.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.32), lineWidth: 1)
                )
        )
    }

    // MARK: - Tab 1: Organize Apps into Folders & Dividers

    private var organizeTabContent: some View {
        HStack(spacing: 0) {
            // Left Sidebar: Collections & Folders
            VStack(alignment: .leading, spacing: 6) {
                sidebarButton(
                    filter: .all,
                    icon: "square.grid.2x2.fill",
                    color: .accentColor,
                    title: "Все иконки",
                    count: store.visibleLiveItemCount
                )

                sidebarButton(
                    filter: .rootOnly,
                    icon: "tray.fill",
                    color: .secondary,
                    title: "Без папки (в корне)",
                    count: rootDirectItemCount
                )
                .dropDestination(for: String.self) { dropped, _ in
                    guard let nodeID = dropped.first else { return false }
                    store.moveNode(nodeID: nodeID, toFolderID: nil)
                    return true
                } isTargeted: { targeted in
                    targetedSidebarFilter = targeted ? .rootOnly : nil
                }

                HStack {
                    Text("ОСНОВНЫЕ ПАПКИ")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            store.autoSortAppsIntoCategories()
                            sidebarFilter = .all
                        }
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Автосортировка: создать основные папки и разложить приложения по категориям")

                    Button {
                        store.presentCreateFolder(parentFolderID: nil)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Создать основную папку")
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 2)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        let folders = store.topLevelFolders()
                        if folders.isEmpty {
                            VStack(spacing: 7) {
                                Text("Папок пока нет")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        store.autoSortAppsIntoCategories()
                                        sidebarFilter = .all
                                    }
                                } label: {
                                    Label("Автосортировка", systemImage: "wand.and.stars")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button {
                                    store.presentCreateFolder(parentFolderID: nil)
                                } label: {
                                    Label("Создать папку", systemImage: "folder.badge.plus")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        } else {
                            ForEach(folders) { folder in
                                sidebarFolderRow(folder)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                Divider().opacity(0.4)

                // Quick actions in sidebar footer (Auto-sort + Collect + Open Menu)
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            store.autoSortAppsIntoCategories()
                            sidebarFilter = .all
                        }
                    } label: {
                        Label("Автосортировка", systemImage: "wand.and.stars")
                            .font(.system(size: 11.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Автоматически разложить все приложения по основным папкам-категориям")

                    HStack(spacing: 6) {
                        Button {
                            store.autoCollectAllIcons()
                        } label: {
                            HStack(spacing: 4) {
                                if store.isAutoCollecting {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "tray.and.arrow.down.fill")
                                }
                                Text("Собрать")
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(store.isAutoCollecting)

                        Button {
                            onOpenMenuBarPopover()
                        } label: {
                            Image(systemName: "menubar.arrow.up.rectangle")
                                .font(.system(size: 11.5, weight: .semibold))
                                .frame(width: 24)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Открыть меню Foldie")
                    }

                    if let msg = store.autoCollectMessage {
                        Text(msg)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
            }
            .padding(12)
            .frame(width: 224)
            .background(Color.primary.opacity(0.03))

            Divider().opacity(0.45)

            // Right Pane: Sortable List of Icons & Dividers
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(currentScopeTitle)
                        .font(.system(size: 14, weight: .bold))

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("Поиск...", text: $localSearch)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .frame(width: 120)
                        if !localSearch.isEmpty {
                            Button { localSearch = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))

                    Button {
                        store.permissions.openMenuBarSettings()
                    } label: {
                        Label("Строка меню macOS", systemImage: "menubar.rectangle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Открыть системный список «Разрешить в строке меню» в настройках macOS")

                    Button {
                        let parentID: UUID? = if case .folder(let id) = sidebarFilter { id } else { nil }
                        store.presentCreateDivider(parentFolderID: parentID)
                    } label: {
                        Label("Разделитель", systemImage: "minus.rectangle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        store.refreshItems(captureThumbnails: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11.5))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Обновить список иконок")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().opacity(0.4)

                ScrollView {
                    LazyVStack(spacing: 5) {
                        let nodes = filteredRightPaneNodes
                        if nodes.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.tertiary)
                                Text("Здесь пока пусто")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text("Перетащите сюда иконки из списка «Все иконки» или назначьте папку через меню «В папку ▾».")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 300)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else {
                            ForEach(nodes) { node in
                                organizerNodeRow(node)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func sidebarButton(
        filter: SidebarFilter,
        icon: String,
        color: Color,
        title: String,
        count: Int
    ) -> some View {
        let isSelected = sidebarFilter == filter
        let isTargeted = targetedSidebarFilter == filter
        return Button {
            sidebarFilter = filter
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : color)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)

                Spacer()

                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isTargeted
                            ? Color.accentColor.opacity(0.22)
                            : (isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarFolderRow(_ folder: FoldieFolder) -> some View {
        let filter = SidebarFilter.folder(folder.id)
        let isSelected = sidebarFilter == filter
        let isTargeted = targetedSidebarFilter == filter
        let isActiveInMenuBar = store.swipedFolderID == folder.id

        return HStack(spacing: 6) {
            Image(systemName: folder.symbolName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(folder.accentColor)
                .frame(width: 17)

            Text(folder.name)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)

            Spacer(minLength: 2)

            if isActiveInMenuBar {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .help("Сейчас активна в строке меню")
            }

            HStack(spacing: 3) {
                Button {
                    store.toggleFolderPinnedInMenuBar(id: folder.id)
                } label: {
                    Image(systemName: folder.showInMenuBar ? "pin.fill" : "pin")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(folder.showInMenuBar ? folder.accentColor : .secondary.opacity(0.65))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(folder.showInMenuBar
                      ? "Убрать отдельную иконку этой папки из строки меню"
                      : "Закрепить эту папку отдельной иконкой в строке меню")

                Button {
                    store.moveMainFolder(id: folder.id, up: true)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 13, height: 14)
                }
                .buttonStyle(.plain)
                .help("Выше в порядке свайпа")

                Button {
                    store.moveMainFolder(id: folder.id, up: false)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 13, height: 14)
                }
                .buttonStyle(.plain)
                .help("Ниже в порядке свайпа")
            }

            Text("\(store.countVisibleItems(in: folder))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isTargeted
                        ? folder.accentColor.opacity(0.24)
                        : (isSelected ? folder.accentColor.opacity(0.16) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isTargeted ? folder.accentColor : Color.clear, lineWidth: 1.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            sidebarFilter = filter
        }
        .dropDestination(for: String.self) { dropped, _ in
            guard let nodeID = dropped.first else { return false }
            store.moveNode(nodeID: nodeID, toFolderID: folder.id)
            return true
        } isTargeted: { targeted in
            targetedSidebarFilter = targeted ? filter : nil
        }
        .contextMenu {
            Button {
                store.toggleFolderPinnedInMenuBar(id: folder.id)
            } label: {
                Label(
                    folder.showInMenuBar ? "Убрать отдельную иконку из строки меню" : "Закрепить отдельной иконкой в строке меню",
                    systemImage: folder.showInMenuBar ? "pin.slash" : "pin.fill"
                )
            }
            Button {
                store.selectSwipedFolder(isActiveInMenuBar ? nil : folder.id)
            } label: {
                Label(
                    isActiveInMenuBar ? "Показать все папки в Foldie" : "Выбрать активной в Foldie (свайп)",
                    systemImage: "menubar.rectangle"
                )
            }
            Divider()
            Button {
                store.presentEditFolder(folder)
            } label: {
                Label("Редактировать папку", systemImage: "pencil")
            }
            Button(role: .destructive) {
                if sidebarFilter == filter {
                    sidebarFilter = .all
                }
                store.deleteFolder(id: folder.id)
            } label: {
                Label("Удалить папку (иконки останутся)", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func organizerNodeRow(_ node: FoldieNode) -> some View {
        switch node {
        case .item(let key):
            OrganizerItemRow(store: store, itemKey: key, nodeID: node.id)
        case .divider(let divider):
            HStack(spacing: 8) {
                Rectangle().fill(Color.primary.opacity(0.16)).frame(height: 1)
                Text(divider.label.isEmpty ? "РАЗДЕЛИТЕЛЬ" : divider.label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Rectangle().fill(Color.primary.opacity(0.16)).frame(height: 1)

                Button {
                    store.nudgeNode(nodeID: node.id, up: true)
                } label: {
                    Image(systemName: "arrow.up").font(.system(size: 10))
                }
                .buttonStyle(.plain)

                Button {
                    store.nudgeNode(nodeID: node.id, up: false)
                } label: {
                    Image(systemName: "arrow.down").font(.system(size: 10))
                }
                .buttonStyle(.plain)

                Button {
                    store.presentEditDivider(divider)
                } label: {
                    Image(systemName: "pencil").font(.system(size: 10.5))
                }
                .buttonStyle(.plain)

                Button {
                    store.deleteDivider(id: divider.id)
                } label: {
                    Image(systemName: "trash").font(.system(size: 10.5)).foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
            .draggable(node.id)
            .dropDestination(for: String.self) { dropped, _ in
                guard let id = dropped.first, id != node.id else { return false }
                store.moveNode(nodeID: id, before: node.id)
                return true
            }
        case .folder(let folder):
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(folder.accentColor.opacity(0.18))
                    Image(systemName: folder.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(folder.accentColor)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Папка • \(store.countVisibleItems(in: folder)) ик.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Открыть") {
                    sidebarFilter = .folder(folder.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.045)))
            .dropDestination(for: String.self) { dropped, _ in
                guard let id = dropped.first, id != node.id else { return false }
                store.moveNode(nodeID: id, toFolderID: folder.id)
                return true
            }
        }
    }

    // MARK: - Tab 2: Appearance & Behavior

    private var appearanceTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Quick action banner for menu bar visibility & auto-collect
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                        Image(systemName: "menubar.rectangle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Управление строкой меню")
                            .font(.system(size: 14, weight: .semibold))
                        Text(store.hider.isCurrentlyHiding
                             ? "Иконки сейчас скрыты внутри Foldie."
                             : "Иконки сейчас показаны в строке меню.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        store.hider.pulseHighlight()
                    } label: {
                        Label("Подсветить иконку", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        store.autoCollectAllIcons()
                    } label: {
                        Label("Собрать все иконки", systemImage: "tray.and.arrow.down.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isAutoCollecting)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
                        )
                )

                // Reuse settings controls in a clean grid
                SettingsView(store: store)
            }
            .padding(16)
        }
    }

    // MARK: - Tab 3: Permissions & Onboarding

    private var permissionsTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Разрешения macOS")
                    .font(.system(size: 17, weight: .bold))
                Text("Foldie работает полностью на вашем Mac. Разрешения используются исключительно для обнаружения и клика по иконкам строки меню.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                permissionBox(
                    icon: "hand.raised.fill",
                    color: .orange,
                    title: "Универсальный доступ",
                    description: "Необходим для автоматического сбора иконок в Foldie и для кликов по скрытым иконкам.",
                    granted: store.permissions.hasAccessibility,
                    onRequest: {
                        store.permissions.requestAccessibilityIfNeeded()
                    },
                    secondaryActionTitle: store.permissions.hasAccessibility ? nil : "Сбросить старую запись",
                    onSecondaryAction: {
                        store.permissions.resetStaleAccessibilityAndRequest()
                    }
                )

                permissionBox(
                    icon: "rectangle.dashed.badge.record",
                    color: .blue,
                    title: "Запись экрана",
                    description: "Позволяет определять точные названия сторонних приложений и показывать живые миниатюры иконок.",
                    granted: store.permissions.hasScreenRecording,
                    onRequest: {
                        store.permissions.requestScreenRecordingIfNeeded()
                    },
                    secondaryActionTitle: nil,
                    onSecondaryAction: nil
                )
            }

            // Drag & drop helper to add Foldie.app directly into System Settings -> Accessibility
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("Добавить перетаскиванием в «Универсальный доступ»")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    if store.permissions.hasAccessibility {
                        Text("Уже активно")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.green)
                    }
                }

                Text("Откройте окно «Универсальный доступ» рядом и просто перетащите карточку Foldie.app прямо в список разрешённых приложений.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                DraggableFoldieAppChip(compact: false) {
                    store.permissions.openAccessibilitySettings()
                }
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )

            HStack {
                Button {
                    store.recheckPermissions()
                } label: {
                    Label("Проверить статусы заново", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    store.onRequestShowOnboarding?()
                } label: {
                    Label("Пройти онбординг заново", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { break }
                let hadAX = store.permissions.hasAccessibility
                store.permissions.refresh()
                if !hadAX && store.permissions.hasAccessibility {
                    store.refreshItems(captureThumbnails: false)
                }
            }
        }
    }

    private func permissionBox(
        icon: String,
        color: Color,
        title: String,
        description: String,
        granted: Bool,
        onRequest: @escaping () -> Void,
        secondaryActionTitle: String?,
        onSecondaryAction: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: granted ? "checkmark.shield.fill" : icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(granted ? .green : color)
                Spacer()
                Text(granted ? "Выдано ✓" : "Не выдано")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(granted ? .green : color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill((granted ? Color.green : color).opacity(0.14)))
            }

            Text(title)
                .font(.system(size: 14, weight: .semibold))

            Text(description)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if !granted {
                HStack(spacing: 8) {
                    Button("Выдать разрешение") {
                        onRequest()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if let secondaryActionTitle, let onSecondaryAction {
                        Button(secondaryActionTitle) {
                            onSecondaryAction()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 165)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(granted ? Color.green.opacity(0.32) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private var rootDirectItemCount: Int {
        store.config.rootNodes.filter {
            if case .item(let key) = $0 { return store.isItemVisibleInUI(key: key) }
            return false
        }.count
    }

    private var currentScopeTitle: String {
        switch sidebarFilter {
        case .all: return "Все собранные иконки"
        case .rootOnly: return "Без папки (в корне)"
        case .folder(let id): return store.folder(byID: id)?.name ?? "Папка"
        }
    }

    private var filteredRightPaneNodes: [FoldieNode] {
        let query = localSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return store.matchingItemKeys(for: query).map { .item(key: $0) }
        }

        switch sidebarFilter {
        case .all:
            var flattened: [FoldieNode] = []
            func collect(_ nodes: [FoldieNode]) {
                for node in nodes {
                    switch node {
                    case .item(let key):
                        if store.isItemVisibleInOrganizer(key: key) { flattened.append(node) }
                    case .folder(let folder):
                        collect(folder.children)
                    case .divider:
                        flattened.append(node)
                    }
                }
            }
            collect(store.config.rootNodes)
            return flattened

        case .rootOnly:
            return store.config.rootNodes.filter { node in
                switch node {
                case .item(let key): return store.isItemVisibleInOrganizer(key: key)
                case .divider: return true
                case .folder: return false
                }
            }

        case .folder(let id):
            guard let folder = store.folder(byID: id) else { return [] }
            return folder.children.filter { node in
                switch node {
                case .item(let key): return store.isItemVisibleInOrganizer(key: key)
                case .folder, .divider: return true
                }
            }
        }
    }
}

private struct OrganizerItemRow: View {
    @ObservedObject var store: FoldieStore
    let itemKey: String
    let nodeID: String

    @State private var isDropTargeted = false

    private var liveItem: MenuBarItem? {
        store.liveItemsByKey[itemKey]
    }

    private var currentFolder: FoldieFolder? {
        guard let fid = store.parentFolderID(ofNodeID: nodeID) else { return nil }
        return store.folder(byID: fid)
    }

    var body: some View {
        VStack(spacing: 2) {
            if isDropTargeted {
                Capsule().fill(Color.accentColor).frame(height: 2).padding(.horizontal, 8)
            }

            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                MenuBarIconPreview(
                    item: liveItem,
                    fallbackAppIcon: store.resolvedAppIcon(forItemKey: itemKey),
                    iconStyle: store.config.preferences.iconStyle,
                    size: 24
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.displayName(forItemKey: itemKey))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(store.subtitle(forItemKey: itemKey))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // One-click folder assignment picker right on every row!
                Menu {
                    Button {
                        store.moveNode(nodeID: nodeID, toFolderID: nil)
                    } label: {
                        Label("Без папки (в корень)", systemImage: "tray")
                    }

                    let folders = store.allFolders()
                    if !folders.isEmpty {
                        Divider()
                        ForEach(folders) { folder in
                            Button {
                                store.moveNode(nodeID: nodeID, toFolderID: folder.id)
                            } label: {
                                Label(folder.name, systemImage: folder.symbolName)
                            }
                        }
                    }

                    Divider()

                    Button {
                        store.presentCreateFolder(parentFolderID: nil)
                    } label: {
                        Label("Создать новую папку...", systemImage: "folder.badge.plus")
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let folder = currentFolder {
                            Image(systemName: folder.symbolName)
                                .font(.system(size: 10.5))
                                .foregroundStyle(folder.accentColor)
                            Text(folder.name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        } else {
                            Image(systemName: "folder")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                            Text("В папку")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(currentFolder?.accentColor.opacity(0.14) ?? Color.primary.opacity(0.06))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                HStack(spacing: 2) {
                    Button {
                        store.nudgeNode(nodeID: nodeID, up: true)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Поднять выше")

                    Button {
                        store.nudgeNode(nodeID: nodeID, up: false)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Опустить ниже")
                }
                .foregroundStyle(.secondary)

                Button {
                    store.activateItem(key: itemKey, rightClick: false)
                } label: {
                    Image(systemName: liveItem != nil ? "cursorarrow.click" : "play.circle")
                        .font(.system(size: 12.5))
                        .foregroundStyle(liveItem != nil ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(liveItem == nil && store.resolveApplicationURL(forItemKey: itemKey) == nil)
                .help(liveItem != nil ? "Открыть иконку в строке меню" : "Запустить приложение")

                Toggle("", isOn: Binding(
                    get: { store.isItemEnabledInFoldie(key: itemKey) },
                    set: { store.setItemEnabledInFoldie(key: itemKey, enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Показывать это приложение внутри папки Foldie")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .opacity(store.isItemEnabledInFoldie(key: itemKey) ? 1.0 : 0.55)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.75)
                    )
            )
            .draggable(nodeID)
            .dropDestination(for: String.self) { dropped, _ in
                guard let droppedID = dropped.first, droppedID != nodeID else { return false }
                store.moveNode(nodeID: droppedID, before: nodeID)
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
        }
    }
}
