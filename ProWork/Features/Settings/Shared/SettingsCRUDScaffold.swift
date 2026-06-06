//  SettingsCRUDScaffold.swift
//  ProWork
//  Created by Pronomi.
//  HolidaysView, TodoStatusesView, TaskCategoriesView, and
//  VatRatesView each spelled out the same CRUD orchestration boilerplate:
//      • a "new" button in the toolbar
//      • a Bool `@State` flag for the create sheet
//      • an Optional `@State` for the edit sheet's item
//      • a `ProWorkConfirmation?` for the delete dialog
//      • two `.sheet(...)` modifiers + one confirmation dialog modifier
//  This file pulls those pieces into two shared building blocks so the
//  per-feature views can focus on their unique list/row layout:
//      1. `SettingsCRUDToolbarButton` — the standard "Yeni X" toolbar button
//         (bordered prominent, large control size). Keeps a consistent
//         primary-action look across CRUD screens.
//      2. `settingsCRUDPresenter(...)` view modifier — wires the three
//         host-owned state bindings (create-flag, edit-item, confirmation)
//         to the two sheets + one dialog so the call site has a single
//         line of modifier glue.

import SwiftUI

// MARK: - Form staleness contract (-2 documentation)
// All settings forms (HolidayFormView, TaskCategoryFormView,
// TodoStatusFormView, VatRateFormView, ExchangeRateFormView,
// PriceListFormView, PriceListRowFormView, etc.) follow the same
// snapshot contract:
//   • The form's `mode` carries an immutable snapshot of the record at
//     the moment the parent opened the sheet (e.g. `.edit(Holiday)`).
//   • Each form copies the relevant fields from that snapshot into its
//     own `@State` properties exactly once, inside `loadInitialValues()`.
//   • Subsequent edits in the form only mutate local @State; the
//     persistence step happens via the `onSave` callback when the user
//     confirms.
// The review note about "parent mutating the record while the sheet is
// open" does not apply in practice because every CRUD screen presents
// edits via `.sheet(item:)`. SwiftUI re-instantiates the sheet body
// whenever the bound item changes identity, so a concurrent update from
// elsewhere will tear down the stale form and rebuild it with the new
// snapshot. The remaining sliver — "parent updates the in-memory item
// without re-emitting through the `item:` binding" — is not a code path
// any current screen hits.
// If a future screen ever opens a form via `isPresented:` with a
// separately-held item, that screen MUST re-emit the binding (e.g.
// `editingItem = updated`) instead of mutating the live record in place,
// or wrap the form in its own state-machine sheet enum (see
// BillingRunsView's `ActiveSheet`).

/// Standardise the "new X" primary action button used by every CRUD screen
/// (Holidays/TodoStatuses/TaskCategories/VatRates). Centralising the
/// button-style + control-size pair keeps a future visual tweak to all
/// CRUD toolbars to a one-line change here.
struct SettingsCRUDToolbarButton: View {
    let title: String
    let systemImage: String
    let isDisabled: Bool
    let disabledHelp: String?
    let enabledHelp: String?
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        isDisabled: Bool = false,
        disabledHelp: String? = nil,
        enabledHelp: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.disabledHelp = disabledHelp
        self.enabledHelp = enabledHelp
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ProWorkButtonLabel(title: title, systemImage: systemImage, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isDisabled)
        .help(helpText)
    }

    private var helpText: String {
        if isDisabled, let disabledHelp { return disabledHelp }
        return enabledHelp ?? ""
    }
}

/// View modifier that wires the standard CRUD sheet/dialog state to its
/// owning view in one place. Each binding stays on the host view (so the
/// host can also drive them programmatically — e.g. open the create sheet
/// in response to an empty-state button), but the actual `.sheet(...)` and
/// `.proWorkConfirmationDialog(...)` plumbing is provided here.
struct SettingsCRUDPresenterModifier<Item: Identifiable, CreateForm: View, EditForm: View>: ViewModifier {
    @Binding var isShowingCreate: Bool
    @Binding var editingItem: Item?
    @Binding var confirmation: ProWorkConfirmation?
    @ViewBuilder var createForm: () -> CreateForm
    @ViewBuilder var editForm: (Item) -> EditForm

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isShowingCreate, content: createForm)
            .sheet(item: $editingItem, content: editForm)
            .proWorkConfirmationDialog($confirmation)
    }
}

extension View {
    /// Apply the standard Settings CRUD sheet/dialog presentation glue.
    /// Use with the per-feature bindings, e.g.
    /// ```swift
    /// .settingsCRUDPresenter(
    ///     isShowingCreate: $isShowingCreate,
    ///     editingItem: $editingHoliday,
    ///     confirmation: $confirmation,
    ///     createForm: { HolidayFormView(mode: .create) { ... } },
    ///     editForm: { HolidayFormView(mode: .edit($0)) { ... } }
    /// )
    /// ```
    func settingsCRUDPresenter<Item: Identifiable, CreateForm: View, EditForm: View>(
        isShowingCreate: Binding<Bool>,
        editingItem: Binding<Item?>,
        confirmation: Binding<ProWorkConfirmation?>,
        @ViewBuilder createForm: @escaping () -> CreateForm,
        @ViewBuilder editForm: @escaping (Item) -> EditForm
    ) -> some View {
        modifier(SettingsCRUDPresenterModifier(
            isShowingCreate: isShowingCreate,
            editingItem: editingItem,
            confirmation: confirmation,
            createForm: createForm,
            editForm: editForm
        ))
    }
}
