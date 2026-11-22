import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: FoldieStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionCard(title: "Режим раскрытия меню") {
                    HStack {
                        Text("Вид выпадающего меню")
                            .font(.system(size: 12.5, weight: .medium))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { store.config.preferences.displayMode },
                            set: { store.setDisplayMode($0) }
                        )) {
                            ForEach(DisplayMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.symbolName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 190)
                    }

                    if store.config.preferences.displayMode == .cylinder {
                        Divider().opacity(0.4)
                        HStack {
                            Text("Внутри 3D-цилиндра")
                                .font(.system(size: 12))
                            Spacer()
                            Picker("", selection: Binding(
                                get: { store.config.preferences.cylinderScope },
                                set: { store.setCylinderScope($0) }
                            )) {
                                ForEach(CylinderScope.allCases) { scope in
                                    Text(scope.title).tag(scope)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .controlSize(.small)
                            .frame(width: 190)
                        }
                    }

                    Divider().opacity(0.4)

                    HStack {
                        Text("Стиль иконок")
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { store.config.preferences.iconStyle },
                            set: { store.setIconStyle($0) }
                        )) {
                            ForEach(IconStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 190)
                    }

                    Divider().opacity(0.4)

                    HStack {
                        Text("Вид в строке меню")
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { store.config.preferences.statusBarLabelMode },
                            set: { store.setStatusBarLabelMode($0) }
                        )) {
                            ForEach(StatusBarLabelMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 210)
                    }

                    Divider().opacity(0.4)

                    HStack {
                        Text("Форма капсулы")
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { store.config.preferences.capsuleShape },
                            set: { store.setCapsuleShape($0) }
                        )) {
                            ForEach(CapsuleShapeStyle.allCases) { shape in
                                Text(shape.title).tag(shape)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 225)
                    }

                    Divider().opacity(0.4)

                    Toggle("Свайп влево/вправо для переключения папок", isOn: Binding(
                        get: { store.config.preferences.enableMenuBarSwipe },
                        set: { store.setEnableMenuBarSwipe($0) }
                    ))
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Toggle("Звуковые эффекты (клик, свайп, барабан)", isOn: Binding(
                        get: { store.config.preferences.enableSounds },
                        set: { store.setEnableSounds($0) }
                    ))
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                sectionCard(title: "Поведение строки меню") {
                    Toggle(isOn: Binding(
                        get: { store.config.preferences.hideMenuBarIcons },
                        set: { store.setHideMenuBarIcons($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Скрывать иконки в Foldie")
                                .font(.system(size: 12.5, weight: .medium))
                            Text("Прячет все иконки слева от папки Foldie, оставляя строку меню чистой")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Divider().opacity(0.4)

                    HStack {
                        Text("Автоскрытие после клика")
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { store.config.preferences.autoRehideMode },
                            set: { store.setAutoRehideMode($0) }
                        )) {
                            ForEach(AutoRehideMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 155)
                    }

                    Divider().opacity(0.4)

                    Toggle("Показывать системные иконки macOS", isOn: Binding(
                        get: { store.config.preferences.showSystemItems },
                        set: { store.setShowSystemItems($0) }
                    ))
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Toggle("Показывать неактивные (офлайн) иконки", isOn: Binding(
                        get: { store.config.preferences.showOfflineItems },
                        set: { store.setShowOfflineItems($0) }
                    ))
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                sectionCard(title: "Иконка Foldie в строке меню") {
                    HStack(spacing: 8) {
                        ForEach(FoldiePalette.statusBarSymbols, id: \.symbol) { entry in
                            let selected = store.config.preferences.statusIconSymbol == entry.symbol
                            Button {
                                store.setStatusIconSymbol(entry.symbol)
                            } label: {
                                Image(systemName: entry.symbol)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(selected ? Color.accentColor : .primary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.2)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(entry.name)
                        }
                    }
                }

                sectionCard(title: "Разрешения macOS") {
                    permissionRow(
                        title: "Универсальный доступ",
                        subtitle: "Нужен для клика по скрытым иконкам",
                        granted: store.permissions.hasAccessibility,
                        onRequest: {
                            store.permissions.requestAccessibilityIfNeeded()
                        }
                    )

                    if !store.permissions.hasAccessibility {
                        DraggableFoldieAppChip(compact: true) {
                            store.permissions.openAccessibilitySettings()
                        }
                    }

                    Divider().opacity(0.4)

                    permissionRow(
                        title: "Запись экрана",
                        subtitle: "Отображает оригинальные миниатюры иконок строки меню",
                        granted: store.permissions.hasScreenRecording,
                        onRequest: {
                            store.permissions.requestScreenRecordingIfNeeded()
                        }
                    )

                    Button {
                        store.recheckPermissions()
                    } label: {
                        Label("Проверить разрешения заново", systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5))
                    }
                    .buttonStyle(.link)
                }

                sectionCard(title: "Обновления") {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Текущая версия: v\(store.updater.currentVersion)")
                                .font(.system(size: 12, weight: .semibold))
                            updateStatusLabel
                        }

                        Spacer()

                        updateActionButtons
                    }

                    if case .downloading(_, let progress) = store.updater.state {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    }

                    Divider().opacity(0.4)

                    Toggle("Проверять обновления автоматически (GitHub Releases)", isOn: Binding(
                        get: { store.config.preferences.autoCheckUpdates },
                        set: { store.setAutoCheckUpdates($0) }
                    ))
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                sectionCard(title: "Приложение") {
                    Toggle("Запускать Foldie при входе в систему", isOn: Binding(
                        get: { store.config.preferences.launchAtLogin },
                        set: { store.setLaunchAtLogin($0) }
                    ))
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Divider().opacity(0.4)

                    HStack {
                        Button("Показать онбординг") {
                            store.onRequestClosePanel?()
                            store.onRequestShowOnboarding?()
                        }
                        .controlSize(.small)

                        Button("Сбросить порядок") {
                            store.resetLayout()
                        }
                        .controlSize(.small)

                        Spacer()

                        Button("Выйти") {
                            NSApp.terminate(nil)
                        }
                        .controlSize(.small)
                        .foregroundStyle(.red)
                    }
                }
            }
            .padding(12)
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 9) {
                content()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.75)
                    )
            )
        }
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        granted: Bool,
        onRequest: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(granted ? .green : .orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Text("Выдано")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Button("Выдать") {
                    onRequest()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
    }

    @ViewBuilder
    private var updateStatusLabel: some View {
        switch store.updater.state {
        case .idle:
            Text("Автообновление из github.com/temakubik/foldie")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        case .checking:
            Text("Проверяем наличие новой версии...")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        case .upToDate:
            Text("Установлена последняя версия ✓")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.green)
        case .available(let release):
            Text("Доступна новая версия v\(release.version)")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        case .downloading(let version, let progress):
            Text("Загружаем v\(version)... \(Int(progress * 100))%")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.accentColor)
        case .installing(let version):
            Text("Устанавливаем v\(version) и перезапускаем Foldie...")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.accentColor)
        case .error(let msg):
            Text(msg)
                .font(.system(size: 10.5))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var updateActionButtons: some View {
        switch store.updater.state {
        case .available(let release):
            Button("Обновить до v\(release.version)") {
                store.updater.installAvailableUpdate()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .checking, .downloading, .installing:
            ProgressView()
                .controlSize(.small)
        default:
            Button("Проверить") {
                store.updater.checkForUpdates(userInitiated: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
