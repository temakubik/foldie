import AppKit
import SwiftUI

/// Built-in interactive Help & Guide tab inside Foldie's Settings window.
struct HelpGuideView: View {
    @ObservedObject var store: FoldieStore
    let onOpenPermissionsTab: () -> Void

    @State private var copiedCommandID: String?

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.2.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerBanner

                guideCard(
                    icon: "eye.slash.fill",
                    color: .blue,
                    title: "Как Foldie скрывает иконки со строки меню"
                ) {
                    bulletRow(
                        icon: "arrow.right.to.line",
                        text: "Foldie прячет все иконки, которые находятся слева от его капсулы. Всё, что стоит справа от Foldie, остаётся всегда на виду."
                    )
                    bulletRow(
                        icon: "sparkles",
                        text: "При завершении онбординга, при «Автосортировке» и при включении скрытия Foldie сам прижимается к правому краю строки меню — даже без системных разрешений."
                    )
                    bulletRow(
                        icon: "command",
                        text: "Если хотите настроить границу вручную: зажмите ⌘ (Command) и перетащите капсулу Foldie ближе к часам или перетащите нужные иконки влево от Foldie."
                    )

                    HStack(spacing: 8) {
                        Button {
                            store.autoCollectAllIcons()
                        } label: {
                            Label("Собрать и скрыть иконки сейчас", systemImage: "tray.and.arrow.down.fill")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(store.isAutoCollecting)

                        Button {
                            store.permissions.openMenuBarSettings()
                        } label: {
                            Label("Строка меню macOS", systemImage: "menubar.rectangle")
                                .font(.system(size: 11.5))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }

                guideCard(
                    icon: "hand.draw.fill",
                    color: .purple,
                    title: "Управление трекпадом, мышкой и клавиатурой"
                ) {
                    gestureRow(
                        badge: "Наведение / ЛКМ",
                        detail: "Открыть выпадающее меню Foldie или закреплённой папки."
                    )
                    gestureRow(
                        badge: "ПКМ по капсуле",
                        detail: "Открыть это окно настроек Foldie."
                    )
                    gestureRow(
                        badge: "Клик по приложению",
                        detail: "Левый и правый клик по приложению внутри папки передаются напрямую в само приложение (открывая его меню)."
                    )
                    gestureRow(
                        badge: "Свайп (трекпад)",
                        detail: "Свайп двумя пальцами влево/вправо по капсуле или открытому меню переключает основные папки."
                    )
                    gestureRow(
                        badge: "Свайп (мышка)",
                        detail: "Горизонтальное колёсико, Shift + обычное колёсико, либо зажать ЛКМ и потянуть влево/вправо прямо по капсуле (⌘ + перетаскивание перемещает иконку по строке меню)."
                    )
                    gestureRow(
                        badge: "3D-Цилиндр",
                        detail: "Прокрутка трекпадом или колёсиком, перетаскивание вверх/вниз и клавиши ↑ / ↓ / Enter / Esc."
                    )
                }

                guideCard(
                    icon: "folder.badge.gearshape",
                    color: .orange,
                    title: "Папки, автосортировка и внешний вид"
                ) {
                    bulletRow(
                        icon: "wand.and.stars",
                        text: "Кнопка «Автосортировка» во вкладке «Сортировка и папки» раскладывает приложения по 7 категориям (ИИ и разработка, Сеть и VPN, Связь, Продуктивность, Утилиты, Система, Прочее)."
                    )
                    bulletRow(
                        icon: "pin.fill",
                        text: "Нажмите значок булавки рядом с любой папкой, чтобы вынести её отдельной цветной капсулой прямо в строку меню."
                    )
                    bulletRow(
                        icon: "paintbrush.fill",
                        text: "Во вкладке «Поведение и вид» настраиваются режим «Список / 3D-Цилиндр», отображение «Иконка и текст / Только иконка», форма скругления капсулы, монохромные иконки, свайпы и тактильные звуки."
                    )
                }

                guideCard(
                    icon: "lock.shield.fill",
                    color: .green,
                    title: "Установка на другой Mac и разрешения (macOS 14–27)"
                ) {
                    Text("1. Если macOS предупреждает при первом запуске (карантин после скачивания из браузера):")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("Откройте через правый клик → «Открыть» или выполните в Терминале команду снятия карантина:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    commandCopyRow(
                        id: "quarantine",
                        command: "xattr -dr com.apple.quarantine /Applications/Foldie.app"
                    )

                    Divider().opacity(0.4).padding(.vertical, 2)

                    Text("2. Универсальный доступ (macOS 14–26):")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("Нужен, чтобы клик по приложению в папке открывал его меню строки меню. Если после обновления сборки тумблер в macOS включён, а статус в Foldie показывает «Не выдано», нажмите «Сбросить старую запись» во вкладке «Разрешения» или выполните:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    commandCopyRow(
                        id: "tccreset",
                        command: "tccutil reset Accessibility com.foldie.app"
                    )

                    Divider().opacity(0.4).padding(.vertical, 2)

                    Text("3. macOS 27.3+ (System & App Protection Override):")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("В macOS 27.3+ Apple перенесла разрешения для сторонних утилит управления в раздел «System & App Protection Override». Если Foldie серый в окне добавления «+», сначала снимите карантин командой выше (либо соберите приложение локально через ./build.sh со своим доверенным сертификатом «Foldie Dev» в «Связке ключей»). Скрытие иконок со строки меню при этом работает автоматически и без этого разрешения.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button {
                            onOpenPermissionsTab()
                        } label: {
                            Label("Перейти во вкладку «Разрешения»", systemImage: "checkmark.shield")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }

                footerLinksCard
            }
            .padding(18)
        }
    }

    private var headerBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#248FFF") ?? .blue, Color(hex: "#5856D6") ?? .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Справка и руководство по Foldie")
                    .font(.system(size: 15, weight: .bold))
                Text("Версия \(appVersion) • Все жесты, настройка скрытия и решение вопросов с разрешениями macOS")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func guideCard<Content: View>(
        icon: String,
        color: Color,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16, alignment: .center)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func gestureRow(badge: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(badge)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(width: 134, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )

            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func commandCopyRow(id: String, command: String) -> some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copiedCommandID = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    if copiedCommandID == id {
                        copiedCommandID = nil
                    }
                }
            } label: {
                Label(
                    copiedCommandID == id ? "Скопировано" : "Скопировать",
                    systemImage: copiedCommandID == id ? "checkmark" : "doc.on.doc"
                )
                .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                )
        )
    }

    private var footerLinksCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Репозиторий и свежие сборки Foldie")
                    .font(.system(size: 12, weight: .semibold))
                Text("github.com/temakubik/foldie")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let release = store.updater.state.availableRelease {
                Button {
                    store.updater.installAvailableUpdate()
                } label: {
                    Label("Обновить до v\(release.version)", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button {
                    store.updater.checkForUpdates(userInitiated: true)
                } label: {
                    Label(
                        store.updater.state == .checking ? "Проверяем..." : "Проверить обновления",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.system(size: 11.5))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.updater.state.isBusy)
            }

            Button {
                if let url = URL(string: "https://github.com/temakubik/foldie") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("GitHub", systemImage: "safari")
                    .font(.system(size: 11.5))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
