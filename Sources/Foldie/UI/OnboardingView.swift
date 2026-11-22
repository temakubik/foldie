import AppKit
import SwiftUI

enum OnboardingFinishDestination {
    case openOrganizer
    case openPopover
}

struct OnboardingView: View {
    @ObservedObject var store: FoldieStore
    let onComplete: (OnboardingFinishDestination) -> Void

    @State private var currentStep: Int = 0
    @State private var permissionTimer: Timer?

    private let totalSteps = 3

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow, state: .active)

            VStack(spacing: 0) {
                topHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                Divider().opacity(0.45)

                Group {
                    switch currentStep {
                    case 0:
                        welcomeStep
                    case 1:
                        permissionsAndCollectStep
                    default:
                        modeAndFinishStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 26)
                .padding(.vertical, 18)

                Divider().opacity(0.45)

                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: 560, height: 550)
        .onAppear {
            store.refreshItems(captureThumbnails: false)
            startPermissionPolling()
        }
        .onDisappear {
            stopPermissionPolling()
        }
    }

    // MARK: - Top Header

    private var topHeader: some View {
        HStack {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#248FFF") ?? .blue, Color(hex: "#4648E8") ?? .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Foldie")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    Text("Настройка • Шаг \(currentStep + 1) из \(totalSteps)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(step == currentStep ? Color.accentColor : Color.primary.opacity(step < currentStep ? 0.35 : 0.14))
                        .frame(width: step == currentStep ? 24 : 8, height: 6)
                        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: currentStep)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentStep = step
                            }
                        }
                }
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Все иконки строки меню — в одной папке")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("Foldie добавляет папку в верхнюю строку меню macOS, собирает в неё все иконки приложений и даёт раскладывать их по внутренним папкам, разделителям или крутить в 3D-цилиндре.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
            }

            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Найдено иконок в строке меню: \(store.visibleLiveItemCount)")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.12))
                        .overlay(Capsule().strokeBorder(Color.green.opacity(0.28), lineWidth: 0.75))
                )

                Button {
                    store.hider.pulseHighlight()
                } label: {
                    Label("Показать папку в меню", systemImage: "sparkles")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 10) {
                featureRow(
                    icon: "tray.and.arrow.down.fill",
                    color: .blue,
                    title: "Автоматический сбор в Foldie",
                    description: "На следующем шаге вы сможете в один клик выдать разрешение и собрать все иконки строки меню внутрь папки Foldie."
                )

                featureRow(
                    icon: "folder.fill.badge.plus",
                    color: .indigo,
                    title: "Удобная сортировка в настройках",
                    description: "Раскладывайте приложения по внутренним папкам и разделителям в отдельном окне настроек или прямо в выпадающем меню."
                )

                featureRow(
                    icon: "cylinder.split.1x2.fill",
                    color: .purple,
                    title: "Список или 3D-Цилиндр (барабан)",
                    description: "Переключайтесь одним кликом между аккуратным списком с папками и вращающимся 3D-барабаном с тактильной отдачей."
                )
            }
        }
    }

    // MARK: - Step 2: Permissions + One-Click Collect All Apps into Foldie

    private var permissionsAndCollectStep: some View {
        VStack(spacing: 13) {
            VStack(spacing: 5) {
                Text("Разрешения и сбор иконок в Foldie")
                    .font(.system(size: 19, weight: .bold, design: .rounded))

                Text("Выдайте разрешения macOS и нажмите кнопку ниже — Foldie сам займёт место в строке меню и соберёт в себя все иконки.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 9) {
                permissionCard(
                    icon: "hand.raised.fill",
                    color: .orange,
                    title: "Универсальный доступ (Accessibility)",
                    badge: "Для автосбора и кликов",
                    description: "Позволяет Foldie автоматически собрать иконки в папку и открывать их меню по клику.",
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

                permissionCard(
                    icon: "rectangle.dashed.badge.record",
                    color: .blue,
                    title: "Запись экрана (Screen Recording)",
                    badge: "Названия и миниатюры",
                    description: "Позволяет видеть реальные названия приложений и живые миниатюры иконок из строки меню.",
                    granted: store.permissions.hasScreenRecording,
                    onRequest: {
                        store.permissions.requestScreenRecordingIfNeeded()
                    }
                )

                if !store.permissions.hasAccessibility || !store.permissions.hasScreenRecording {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Text("Если тумблер в macOS уже включён после обновления сборки — выключите и включите его снова.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Проверить") {
                            store.recheckPermissions()
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 10.5, weight: .semibold))
                    }
                    .padding(.horizontal, 4)
                }
            }

            if let conflictName = store.hider.conflictingAppName {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Запущен \(conflictName) — он прячет иконку Foldie из строки меню.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Закрыть \(conflictName)") {
                        store.hider.quitConflictingManagerAndReveal()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
                )
            }

            // One-click collect action box!
            VStack(spacing: 9) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                        Image(systemName: store.hider.isCurrentlyHiding ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(store.hider.isCurrentlyHiding ? .green : Color.accentColor)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Собрать все приложения в папку Foldie")
                            .font(.system(size: 13, weight: .semibold))
                        Text(store.autoCollectMessage ?? "Foldie сам переместится вправо и спрячет все иконки слева внутрь папки.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    Button {
                        store.autoCollectAllIcons()
                    } label: {
                        if store.isAutoCollecting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.horizontal, 12)
                        } else {
                            Text(store.hider.isCurrentlyHiding ? "Повторить" : "Собрать все")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(store.isAutoCollecting)
                }

                HStack {
                    Button {
                        store.hider.pulseHighlight()
                    } label: {
                        Label("Подсветить иконку Foldie", systemImage: "sparkles")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.link)

                    Spacer()

                    Button {
                        store.permissions.openMenuBarSettings()
                    } label: {
                        Label("Разрешить в строке меню macOS", systemImage: "menubar.rectangle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.link)

                    if store.hider.isCurrentlyHiding {
                        Button("Показать иконки") {
                            store.toggleTemporaryReveal()
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.24), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Step 3: Choose Style & Go to App Sorting

    private var modeAndFinishStep: some View {
        VStack(spacing: 15) {
            VStack(spacing: 6) {
                Text("Выберите режим и рассортируйте иконки")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("Переключаться между списком и 3D-цилиндром можно в любой момент. Сейчас можно сразу открыть окно сортировки и разложить приложения по папкам.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                modeChoiceCard(
                    mode: .list,
                    title: "Список с папками",
                    subtitle: "Внутренние папки, разделители, поиск и перетаскивание",
                    symbol: "list.bullet.indent",
                    accent: .blue
                )

                modeChoiceCard(
                    mode: .cylinder,
                    title: "3D-Цилиндр",
                    subtitle: "Вращающийся 3D-барабан с прокруткой трекпадом",
                    symbol: "cylinder.split.1x2.fill",
                    accent: .purple
                )
            }

            VStack(alignment: .leading, spacing: 9) {
                Toggle("Скрывать иконки строки меню внутрь Foldie", isOn: Binding(
                    get: { store.config.preferences.hideMenuBarIcons },
                    set: { store.setHideMenuBarIcons($0) }
                ))
                .font(.system(size: 12.5))
                .toggleStyle(.switch)
                .controlSize(.small)

                Toggle("Показывать системные иконки macOS (Wi-Fi, Звук, Батарея)", isOn: Binding(
                    get: { store.config.preferences.showSystemItems },
                    set: { store.setShowSystemItems($0) }
                ))
                .font(.system(size: 12.5))
                .toggleStyle(.switch)
                .controlSize(.small)

                Toggle("Запускать Foldie автоматически при входе в macOS", isOn: Binding(
                    get: { store.config.preferences.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                .font(.system(size: 12.5))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if currentStep > 0 {
                Button("Назад") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep -= 1
                    }
                }
            } else {
                Button("Пропустить") {
                    finish(destination: .openOrganizer)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep += 1
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("Далее")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    finish(destination: .openPopover)
                } label: {
                    Label("Открыть меню Foldie", systemImage: "menubar.arrow.up.rectangle")
                }
                .buttonStyle(.bordered)

                Button {
                    finish(destination: .openOrganizer)
                } label: {
                    Label("Сортировать приложения", systemImage: "folder.fill.badge.gearshape")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Subcomponents

    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.75)
                )
        )
    }

    private func permissionCard(
        icon: String,
        color: Color,
        title: String,
        badge: String,
        description: String,
        granted: Bool,
        onRequest: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((granted ? Color.green : color).opacity(0.16))
                Image(systemName: granted ? "checkmark.shield.fill" : icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(granted ? .green : color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(badge)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(granted ? .green : color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill((granted ? Color.green : color).opacity(0.14)))
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            if granted {
                Label("Выдано", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.top, 4)
            } else {
                Button("Выдать") {
                    onRequest()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 3)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(granted ? Color.green.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func modeChoiceCard(
        mode: DisplayMode,
        title: String,
        subtitle: String,
        symbol: String,
        accent: Color
    ) -> some View {
        let isSelected = store.config.preferences.displayMode == mode
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                store.setDisplayMode(mode)
            }
        } label: {
            VStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(accent.opacity(isSelected ? 0.22 : 0.10))
                    Image(systemName: symbol)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 52, height: 52)

                VStack(spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? accent : .secondary.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.10) : Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? accent : Color.primary.opacity(0.09), lineWidth: isSelected ? 1.8 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func finish(destination: OnboardingFinishDestination) {
        stopPermissionPolling()
        store.completeOnboarding()
        onComplete(destination)
    }

    private func startPermissionPolling() {
        stopPermissionPolling()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                // Strictly passive check — never triggers ScreenCaptureKit or system permission popups!
                store.permissions.refresh()
                store.refreshItems(captureThumbnails: false)
            }
        }
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
}
