//  TodoStatusFormView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct TodoStatusFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var id: String = UUID().uuidString
    @State private var systemKey: String?
    @State private var name: String = ""
    @State private var color: String = "gray"
    @State private var sortOrderText: String = "0"
    @State private var isSystem: Bool = false
    @State private var isActive: Bool = true
    @State private var showInBoard: Bool = true
    @State private var timerBehavior: TimerBehavior = .none
    @State private var resultBehavior: ResultBehavior = .open
    @State private var createdAt: Date = Date()
    @State private var confirmation: ProWorkConfirmation?

    let mode: TodoStatusFormMode
    let onSave: (TodoStatus) -> Void

    /// Shared with TaskCategoryFormView via
    /// `ProWorkColorPickerOptions`.
    private var colorOptions: [SearchPickerOption] {
        ProWorkColorPickerOptions.searchPickerOptions(localizer: settingsStore)
    }

    private var timerOptions: [SearchPickerOption] {
        [
            SearchPickerOption(id: "none", title: settingsStore.localized("todoStatuses.timer.none", defaultValue: "Değiştirme")),
            SearchPickerOption(id: "start", title: settingsStore.localized("todoStatuses.timer.start", defaultValue: "Başlat")),
            SearchPickerOption(id: "stop", title: settingsStore.localized("todoStatuses.timer.stop", defaultValue: "Durdur"))
        ]
    }

    private var resultOptions: [SearchPickerOption] {
        [
            SearchPickerOption(id: "open", title: settingsStore.localized("todoStatuses.result.open", defaultValue: "Açık")),
            SearchPickerOption(id: "completed", title: settingsStore.localized("todoStatuses.result.completed", defaultValue: "Tamamlandı")),
            SearchPickerOption(id: "cancelled", title: settingsStore.localized("todoStatuses.result.cancelled", defaultValue: "İptal"))
        ]
    }

    private var timerBinding: Binding<String> {
        Binding(
            get: { timerBehavior.rawValue },
            set: { timerBehavior = TimerBehavior(rawValue: $0) ?? .none }
        )
    }

    private var resultBinding: Binding<String> {
        Binding(
            get: { resultBehavior.rawValue },
            set: { resultBehavior = ResultBehavior(rawValue: $0) ?? .open }
        )
    }

    var body: some View {
        ProWorkFormShell(
            title: mode.title(using: settingsStore),
            systemImage: "rectangle.3.group",
            width: FormSheetSize.todoStatusForm.width,
            height: FormSheetSize.todoStatusForm.height
        ) {
            formFields
        } footer: {
            footer
        }
        .onAppear {
            loadInitialValues()
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
            formRow(label: settingsStore.localized("todoStatuses.form.name.label", defaultValue: "Statü Adı")) {
                ProWorkTextField(
                    placeholder: settingsStore.localized("todoStatuses.form.name.placeholder", defaultValue: "Örn: Müşteri Onayında"),
                    text: $name,
                    minHeight: 40
                )
                .frame(width: ProWorkLayout.formScaled(340, using: settingsStore))
            }

            formRow(label: settingsStore.localized("todoStatuses.form.color.label", defaultValue: "Renk")) {
                HStack(spacing: ProWorkLayout.formScaled(10, using: settingsStore)) {
                    Circle()
                        .fill(ProWorkColors.fromName(color))
                        .frame(
                            width: ProWorkLayout.formScaled(14, using: settingsStore),
                            height: ProWorkLayout.formScaled(14, using: settingsStore)
                        )

                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("todoStatuses.form.color.placeholder", defaultValue: "Renk seçin"),
                        items: colorOptions,
                        selectedId: $color,
                        isDisabled: false,
                        showsSearch: false,
                        systemImage: "paintpalette",
                        itemTitle: { $0.title },
                        itemColor: { item in ProWorkColors.fromName(item.id) },
                        matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                    )
                    .frame(width: ProWorkLayout.formScaled(200, using: settingsStore))
                }
            }

            formRow(label: settingsStore.localized("todoStatuses.form.order.label", defaultValue: "Sıra")) {
                ProWorkNumberField(
                    placeholder: "0",
                    text: $sortOrderText,
                    style: .integer(),
                    minHeight: 40
                )
                .frame(width: ProWorkLayout.formScaled(90, using: settingsStore))
            }

            Divider()
                .padding(.vertical, ProWorkLayout.formScaled(4, using: settingsStore))

            formRow(label: settingsStore.localized("todoStatuses.form.visibility.label", defaultValue: "Görünürlük")) {
                VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(8, using: settingsStore)) {
                    ProWorkCheckbox(settingsStore.localized("todoStatuses.form.visibility.active", defaultValue: "Aktif"), isOn: $isActive, boxSize: 22)
                    ProWorkCheckbox(settingsStore.localized("todoStatuses.form.visibility.showInBoard", defaultValue: "Panoda göster"), isOn: $showInBoard, boxSize: 22)
                }
            }

            formRow(label: settingsStore.localized("todoStatuses.form.timerBehavior.label", defaultValue: "Süre Davranışı")) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("todoStatuses.form.timerBehavior.placeholder", defaultValue: "Davranış seçin"),
                    items: timerOptions,
                    selectedId: timerBinding,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "timer",
                    itemTitle: { $0.title },
                    matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }

            formRow(label: settingsStore.localized("todoStatuses.form.resultBehavior.label", defaultValue: "Sonuç Davranışı")) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("todoStatuses.form.resultBehavior.placeholder", defaultValue: "Sonuç seçin"),
                    items: resultOptions,
                    selectedId: resultBinding,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "checkmark.circle",
                    itemTitle: { $0.title },
                    matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }

            if isSystem {
                formRow(label: settingsStore.localized("todoStatuses.form.system.label", defaultValue: "Sistem")) {
                    Text(settingsStore.localized("todoStatuses.form.system.message", defaultValue: "Bu statü sistem statüsüdür; silinemez."))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formRow<Content: View>(
        label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: ProWorkLayout.formScaled(16, using: settingsStore)) {
            Text(label)
                .proWorkTextStyle(.callout, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: ProWorkLayout.formScaled(150, using: settingsStore), alignment: .leading)

            HStack {
                content()
                Spacer(minLength: 0)
            }
            .frame(width: ProWorkLayout.formScaled(410, using: settingsStore), alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        ProWorkFormFooter(
            onCancel: { dismiss() },
            onSave: { save() },
            saveTitle: mode.saveButtonTitle(using: settingsStore),
            saveDisabled: !canSave
        )
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadInitialValues() {
        guard case .edit(let status) = mode else {
            return
        }

        id = status.id
        systemKey = status.systemKey
        name = status.name
        color = status.color ?? "gray"
        sortOrderText = "\(status.sortOrder)"
        isSystem = status.isSystem
        isActive = status.isActive
        showInBoard = status.showInBoard

        if status.startsTimer {
            timerBehavior = .start
        } else if status.stopsTimer {
            timerBehavior = .stop
        } else {
            timerBehavior = .none
        }

        if status.marksCompleted {
            resultBehavior = .completed
        } else if status.marksCancelled {
            resultBehavior = .cancelled
        } else {
            resultBehavior = .open
        }

        createdAt = status.createdAt
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrder = sortOrderText.trimmingCharacters(in: .whitespacesAndNewlines)

        // See TaskCategoryFormView — silent ?? 0 coerced
        // typos into "top of the list" with no feedback. Empty stays at 0;
        // non-empty unparseable input is surfaced.
        let sortOrder: Int
        if trimmedOrder.isEmpty {
            sortOrder = 0
        } else if let parsed = Int(trimmedOrder) {
            sortOrder = parsed
        } else {
            ProWorkToastStore.shared.show(
                settingsStore.localized(
                    "todoStatuses.form.error.invalidSortOrder",
                    defaultValue: "Sıralama numarası tam sayı olmalı."
                ),
                style: .error
            )
            return
        }

        guard !cleanName.isEmpty else {
            return
        }

        let startsTimer = timerBehavior == .start
        let stopsTimer = timerBehavior == .stop

        let marksOpen = resultBehavior == .open
        let marksCompleted = resultBehavior == .completed
        let marksCancelled = resultBehavior == .cancelled

        let status = TodoStatus(
            id: id,
            systemKey: systemKey,
            name: cleanName,
            color: color,
            sortOrder: sortOrder,
            isSystem: isSystem,
            isActive: isActive,
            showInBoard: showInBoard,
            startsTimer: startsTimer,
            stopsTimer: stopsTimer,
            marksOpen: marksOpen,
            marksCompleted: marksCompleted,
            marksCancelled: marksCancelled,
            createdAt: createdAt,
            updatedAt: Date()
        )

        switch mode {
        case .create:
            onSave(status)

        case .edit:
            confirmation = ProWorkConfirmation(
                title: settingsStore.localized("todoStatuses.form.confirm.title", defaultValue: "Değişiklikler kaydedilsin mi?"),
                message: String(format: settingsStore.localized("todoStatuses.form.confirm.message", defaultValue: "'%@' iş akışı statüsündeki değişiklikler kaydedilecek."), status.name),
                confirmTitle: settingsStore.localized("todoStatuses.form.confirm.save", defaultValue: "Kaydet"),
                cancelTitle: settingsStore.localized("todoStatuses.form.confirm.cancel", defaultValue: "Vazgeç")
            ) {
                onSave(status)
            }
        }
    }

    private enum TimerBehavior: String {
        case none
        case start
        case stop
    }

    private enum ResultBehavior: String {
        case open
        case completed
        case cancelled
    }
}
