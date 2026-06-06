//  TodoTimeSessionsView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI
import Combine

struct TodoTimeSessionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = TodoTimeSessionsViewModel()

    let todo: TodoListItem

    @State private var isShowingCreateForm = false
    @State private var editingSession: WorkSessionListItem?

    @State private var confirmation: ProWorkConfirmation?

    @EnvironmentObject private var clockTicker: ProWorkClockTicker

    var body: some View {
        ProWorkFormShell(
            title: todo.title,
            subtitle: settingsStore.localized("todoSessions.title", defaultValue: "Çalışmalar"),
            systemImage: "clock",
            width: FormSheetSize.todoTimeSessionsForm.width,
            height: FormSheetSize.todoTimeSessionsForm.height
        ) {
            summary
            sessionTable
        } footer: {
            footer
        }
        .proWorkToastNotifications(errorMessage: viewModel.errorMessage)
        .onAppear {
            viewModel.load(todoId: todo.id)
        }
        // Previously mirrored clockTicker.halfMinute into
        // a private @State `now`, gated by "has any open session". The copy
        // wasn't necessary — reading clockTicker.halfMinute directly in
        // elapsedSeconds gives the same reactivity without a stale-copy
        // window and SwiftUI batches re-renders to whichever fields the
        // body actually reads.
        .sheet(isPresented: $isShowingCreateForm) {
            WorkSessionFormView(
                mode: .create,
                todos: [todo],
                customers: viewModel.customers,
                projects: viewModel.projects,
                categories: viewModel.categories,
                statuses: viewModel.statuses,
                fixedTodo: todo
            ) { _, todoId, startedAt, endedAt, note, _ in
                if viewModel.createManualSession(
                    todoId: todoId,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    note: note
                ) {
                    isShowingCreateForm = false
                }
            }
        }
        .sheet(item: $editingSession) { session in
            WorkSessionFormView(
                mode: .edit(session),
                todos: [todo],
                customers: viewModel.customers,
                projects: viewModel.projects,
                categories: viewModel.categories,
                statuses: viewModel.statuses,
                fixedTodo: todo
            ) { sessionId, todoId, startedAt, endedAt, note, isManual in
                guard let sessionId else {
                    return
                }

                if viewModel.updateSession(
                    id: sessionId,
                    todoId: todoId,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    note: note,
                    isManual: isManual
                ) {
                    editingSession = nil
                }
            }
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var summary: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
                summaryCard(
                    title: settingsStore.localized("workSessions.summary.totalTime", defaultValue: "Toplam Süre"),
                    value: ProWorkFormatters.durationHHmm(totalSessionSeconds),
                    systemImage: "clock"
                )

                summaryCard(
                    title: settingsStore.localized("workSessions.summary.count", defaultValue: "Kayıt Sayısı"),
                    value: "\(viewModel.sessions.count)",
                    systemImage: "list.bullet.rectangle"
                )

                summaryCard(
                    title: settingsStore.localized("workSessions.source.manual", defaultValue: "Manuel"),
                    value: "\(viewModel.sessions.filter { $0.isManual }.count)",
                    systemImage: "hand.point.up.left"
                )
            }
            .padding(.vertical, ProWorkLayout.scaled(1, using: settingsStore))
        }
    }

    private func summaryCard(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        return HStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            Image(systemName: systemImage)
                .proWorkFont(size: 20)
                .foregroundStyle(.blue)
                .frame(width: ProWorkLayout.scaled(24, using: settingsStore))

            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(3, using: settingsStore)) {
                Text(title)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .proWorkTextStyle(.headline)
                    .monospacedDigit()
            }
        }
        .padding(ProWorkLayout.scaled(14, using: settingsStore))
        .frame(width: ProWorkLayout.scaled(165, using: settingsStore), alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var sessionTable: some View {
        ProWorkGrid(
            items: viewModel.sessions,
            cornerRadius: ProWorkLayout.scaled(12, using: settingsStore),
            header: { tableHeader },
            emptyContent: {
                ProWorkGridEmptyState(
                    systemImage: "clock",
                    title: settingsStore.localized("todoSessions.empty.title", defaultValue: "Henüz çalışma kaydı yok"),
                    message: settingsStore.localized("todoSessions.empty.message", defaultValue: "Kartı çalıştırdığınızda veya manuel çalışma eklediğinizde kayıtlar burada görünecek.")
                )
            },
            row: { session in sessionRow(session) }
        )
    }

    private var tableHeader: some View {
        HStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            Text(settingsStore.localized("workSessions.column.start", defaultValue: "Başlangıç"))
                .frame(width: ProWorkLayout.scaled(150, using: settingsStore), alignment: .leading)

            Text(settingsStore.localized("workSessions.column.end", defaultValue: "Bitiş"))
                .frame(width: ProWorkLayout.scaled(150, using: settingsStore), alignment: .leading)

            Text(settingsStore.localized("workSessions.column.duration", defaultValue: "Süre"))
                .frame(width: ProWorkLayout.scaled(80, using: settingsStore), alignment: .trailing)

            Text(settingsStore.localized("workSessions.column.source", defaultValue: "Kaynak"))
                .frame(width: ProWorkLayout.scaled(80, using: settingsStore), alignment: .leading)

            Text(settingsStore.localized("vat.form.note", defaultValue: "Not"))
                .frame(maxWidth: .infinity, alignment: .leading)

            Color.gridHeaderSpacer(width: ProWorkLayout.scaled(84, using: settingsStore))
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
        .padding(.vertical, ProWorkLayout.scaled(9, using: settingsStore))
        .background(.quaternary.opacity(0.35))
    }

    private func sessionRow(_ session: TodoTimeSession) -> some View {
        HStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            Text(settingsStore.formatDateTime(session.startedAt))
                .proWorkTextStyle(.caption)
                .monospacedDigit()
                .frame(width: ProWorkLayout.scaled(150, using: settingsStore), alignment: .leading)

            Text(endDateText(session))
                .proWorkTextStyle(.caption)
                .monospacedDigit()
                .foregroundStyle(session.endedAt == nil ? ProWorkColors.activeHighlight : .secondary)
                .frame(width: ProWorkLayout.scaled(150, using: settingsStore), alignment: .leading)

            Text(ProWorkFormatters.durationHHmm(durationSeconds(session)))
                .proWorkTextStyle(.caption)
                .monospacedDigit()
                .frame(width: ProWorkLayout.scaled(80, using: settingsStore), alignment: .trailing)

            sourceBadge(session)
                .frame(width: ProWorkLayout.scaled(80, using: settingsStore), alignment: .leading)

            Text(session.note ?? "")
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            rowActions(session)
                .frame(width: ProWorkLayout.scaled(84, using: settingsStore), alignment: .trailing)
        }
        .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
        .padding(.vertical, ProWorkLayout.scaled(9, using: settingsStore))
    }

    private func rowActions(_ session: TodoTimeSession) -> some View {
        HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
            Button {
                editingSession = makeListItem(from: session)
            } label: {
                Image(systemName: "pencil")
                    .proWorkFont(size: 16)
                    .frame(
                        width: ProWorkLayout.scaled(24, using: settingsStore),
                        height: ProWorkLayout.scaled(24, using: settingsStore)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(session.endedAt == nil)
            .help(session.endedAt == nil ? settingsStore.localized("workSessions.form.error.activeEdit", defaultValue: "Aktif çalışma düzenlenemez. Önce çalışmayı durdurmalısınız.") : settingsStore.localized("customers.action.edit", defaultValue: "Düzenle"))

            Button(role: .destructive) {
                askDeleteSession(session)
            } label: {
                Image(systemName: "trash")
                    .proWorkFont(size: 16)
                    .frame(
                        width: ProWorkLayout.scaled(24, using: settingsStore),
                        height: ProWorkLayout.scaled(24, using: settingsStore)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(settingsStore.localized("workSessions.delete.confirm", defaultValue: "Sil"))
        }
    }

    @ViewBuilder
    private func sourceBadge(_ session: TodoTimeSession) -> some View {
        if session.isManual {
            Text(settingsStore.localized("workSessions.source.manual", defaultValue: "Manuel"))
                .proWorkTextStyle(.caption2)
                .padding(.horizontal, ProWorkLayout.scaled(7, using: settingsStore))
                .padding(.vertical, ProWorkLayout.scaled(3, using: settingsStore))
                .background(.orange.opacity(0.16))
                .clipShape(Capsule())
        } else {
            Color.clear
        }
    }

    private var footer: some View {
        HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Button {
                isShowingCreateForm = true
            } label: {
                ProWorkButtonLabel(
                    title: settingsStore.localized("workSessions.action.addManual", defaultValue: "Manuel Çalışma Ekle"),
                    systemImage: "plus",
                    minHeight: 40
                )
            }
            .buttonStyle(.borderedProminent)

            Button {
                viewModel.load(todoId: todo.id)
            } label: {
                ProWorkButtonLabel(
                    title: settingsStore.localized("common.refresh", defaultValue: "Yenile"),
                    systemImage: "arrow.clockwise",
                    minHeight: 40
                )
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                dismiss()
            } label: {
                ProWorkButtonLabel(
                    title: settingsStore.localized("common.close", defaultValue: "Kapat"),
                    systemImage: "xmark",
                    minHeight: 40
                )
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        }
    }

    // Removed unused `hasActiveSession` computed var. The
    // last call site was deleted in an earlier UI sweep but the
    // helper was left orphaned; deleting now so future readers don't
    // wonder which row gate it used to drive.

    private var totalSessionSeconds: Int {
        viewModel.sessions.reduce(0) { total, session in
            total + durationSeconds(session)
        }
    }

    private func durationSeconds(_ session: TodoTimeSession) -> Int {
        if let durationSeconds = session.durationSeconds {
            return durationSeconds
        }

        guard session.endedAt == nil else {
            return 0
        }

        return max(0, Int(clockTicker.halfMinute.timeIntervalSince(session.startedAt)))
    }

    private func endDateText(_ session: TodoTimeSession) -> String {
        guard let endedAt = session.endedAt else {
            return settingsStore.localized("workSessions.status.active", defaultValue: "Aktif")
        }

        return settingsStore.formatDateTime(endedAt)
    }

    private func askDeleteSession(_ session: TodoTimeSession) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("workSessions.delete.title", defaultValue: "Çalışma kaydı silinsin mi?"),
            message: settingsStore.localized("workSessions.delete.message", defaultValue: "Bu çalışma kaydı silinecek. Bu işlem geri alınamaz."),
            confirmTitle: settingsStore.localized("workSessions.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("workSessions.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.deleteSession(id: session.id, refreshFor: todo.id)
        }
    }

    private func makeListItem(from session: TodoTimeSession) -> WorkSessionListItem {
        WorkSessionListItem(
            id: session.id,
            todoId: todo.id,
            todoTitle: todo.title,

            customerName: todo.customerName,
            projectName: todo.projectName,

            statusId: todo.statusId,
            statusName: todo.statusName,
            statusColor: todo.statusColor,
            statusStartsTimer: todo.statusStartsTimer,
            statusStopsTimer: todo.statusStopsTimer,
            statusMarksCompleted: todo.statusMarksCompleted,
            statusMarksCancelled: todo.statusMarksCancelled,

            startedAt: session.startedAt,
            endedAt: session.endedAt,
            durationSeconds: session.durationSeconds,
            isManual: session.isManual,
            note: session.note,

            createdAt: session.createdAt,
            updatedAt: session.updatedAt
        )
    }
}
