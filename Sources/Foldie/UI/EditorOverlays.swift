import SwiftUI

struct FolderEditorOverlay: View {
    @State var state: FoldieStore.FolderEditorState
    let onCancel: () -> Void
    let onSave: (FoldieStore.FolderEditorState) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(state.existingFolderID == nil ? "Новая папка" : "Редактировать папку")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Name field with live preview badge
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill((Color(hex: state.accentHex) ?? .accentColor).opacity(0.20))
                        Image(systemName: state.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: state.accentHex) ?? .accentColor)
                    }
                    .frame(width: 34, height: 34)

                    TextField("Название папки...", text: $state.name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            onSave(state)
                        }
                }

                // Color picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Цвет")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(FoldiePalette.folderColors, id: \.hex) { item in
                            let color = Color(hex: item.hex) ?? .accentColor
                            let isSelected = state.accentHex == item.hex
                            Button {
                                state.accentHex = item.hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 22, height: 22)
                                    if isSelected {
                                        Circle()
                                            .strokeBorder(.white, lineWidth: 2)
                                            .frame(width: 22, height: 22)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(item.name)
                        }
                    }
                }

                // Symbol picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Иконка")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(FoldiePalette.folderSymbols, id: \.self) { symbol in
                            let isSelected = state.symbolName == symbol
                            let accent = Color(hex: state.accentHex) ?? .accentColor
                            Button {
                                state.symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(isSelected ? accent : .primary.opacity(0.75))
                                    .frame(width: 30, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(isSelected ? accent.opacity(0.18) : Color.primary.opacity(0.05))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .strokeBorder(isSelected ? accent : Color.clear, lineWidth: 1.2)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Toggle(isOn: $state.showInMenuBar) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Отдельная иконка в строке меню")
                            .font(.system(size: 12, weight: .medium))
                        Text("Закрепляет эту папку с выбранной иконкой и цветом прямо в верхней панели")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.top, 2)

                HStack {
                    Spacer()
                    Button("Отмена") {
                        onCancel()
                    }
                    .controlSize(.small)

                    Button(state.existingFolderID == nil ? "Создать" : "Сохранить") {
                        onSave(state)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .padding(14)
            .frame(width: 318)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
            )
        }
    }
}

struct DividerEditorOverlay: View {
    @State var state: FoldieStore.DividerEditorState
    let onCancel: () -> Void
    let onSave: (FoldieStore.DividerEditorState) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(state.existingDividerID == nil ? "Новый разделитель" : "Редактировать разделитель")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Подпись (необязательно)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Например: Работа, Система, Связь...", text: $state.label)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            onSave(state)
                        }
                }

                // Live preview
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(height: 1)
                    if !state.label.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(state.label.trimmingCharacters(in: .whitespaces).uppercased())
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Rectangle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(height: 1)
                }
                .padding(.vertical, 6)

                HStack {
                    Spacer()
                    Button("Отмена") {
                        onCancel()
                    }
                    .controlSize(.small)

                    Button(state.existingDividerID == nil ? "Добавить" : "Сохранить") {
                        onSave(state)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(14)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
            )
        }
    }
}
