//  CRUDListViewModel.swift
//  ProWork
//  The "try / load() / errorMessage = nil" loop in typical list-screen
//  ViewModels was duplicated verbatim across seven files (Customers, Projects,
//  Holidays, VatRates, TodoStatuses, TaskCategories, ExchangeRates).
//  This small protocol-extension package keeps that boilerplate in one place.

import Foundation

/// Shared contract for list-screen ViewModels. Candidates must be both
/// `@MainActor` and `ObservableObject`; this constraint is needed so the
/// default extensions used by the protocol can run on the main thread.
///
/// Five VMs still hand-roll the `do/try/load()/errorMessage`
/// boilerplate this protocol exists to eliminate:
///   - TodosViewModel (load takes args + non-Void mutations)
///   - WorkSessionsViewModel (load takes no args but the file uses
///     `loadData()` for historical reasons)
///   - TodoTimeSessionsViewModel (load takes args)
///   - PriceListRowsEditViewModel (compound mutations + reorder)
/// WorkSessionFormViewModel (thin VM)
/// Future cleanup should generalise `performMutation(_:refresh:)` so
/// these VMs can adopt the protocol with a closure-based refresh
/// hook; deferred today because each VM has a slightly different
/// signature and an aggressive rename risks more churn than it
/// saves.
@MainActor
protocol CRUDListViewModel: ObservableObject {
    var errorMessage: String? { get set }
    func load()
}

extension CRUDListViewModel {

    /// Runs the repository mutation; on success calls `load()` and returns
    /// `true`, on failure writes to `errorMessage` and returns `false`.
    /// The view side decides with e.g.
    /// `if viewModel.performMutation({ try ... }) { dismiss() }`.
    ///
    /// `onSuccess` closure fires after `load()` so VMs that need
    /// to set a saved-notice no longer have to repeat the
    /// `if performMutation { savedNotice = … }` boilerplate. The
    /// closure runs on the main actor (the protocol is `@MainActor`),
    /// and is skipped on failure — same semantics as the manual
    /// `if ok { … }` site.
    @discardableResult
    func performMutation(
        _ mutation: () throws -> Void,
        onSuccess: (() -> Void)? = nil
    ) -> Bool {
        do {
            try mutation()
            load()
            errorMessage = nil
            onSuccess?()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// For sequenced mutations (e.g. soft delete), catches the error
    /// without triggering a reload; the caller controls the load call.
    func performMutationWithoutReload(
        _ mutation: () throws -> Void
    ) -> Bool {
        do {
            try mutation()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
