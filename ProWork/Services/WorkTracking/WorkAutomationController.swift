//  WorkAutomationController.swift
//  ProWork
//   Created by Pronomi.

import ApplicationServices
import Combine
import Foundation

@MainActor
final class WorkAutomationController: ObservableObject {
    @Published private(set) var activeSession: ActiveWorkSessionSummary?
    @Published private(set) var pausedSession: ActiveWorkSessionSummary?
    @Published private(set) var quickTodos: [TodoListItem] = []
    @Published private(set) var idleSeconds: TimeInterval = 0
    @Published private(set) var lastAutomationMessage: String?

    private let controlService: WorkSessionControlService
    /// Injectable so tests can substitute a mock that
    /// records `notifyIdleAutoStop` calls without invoking the real
    /// UNUserNotificationCenter.
    private let notificationService: AppNotificationService
    private var settings: AppSettings = .defaults
    /// Fast tick (every 30s) — enough for the idle-threshold check and
    /// firing the action; does no DB queries.
    private var fastTickCancellable: AnyCancellable?
    /// Slow tick (every 2 min) — `refresh()` ile DB'ye sorar. Eskiden
    /// the fast tick was producing 3 DB queries every 30 seconds, even when idle.
    /// olunsa bile.
    private var slowTickCancellable: AnyCancellable?
    private var hasTriggeredIdleStop = false

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    init(
        controlService: WorkSessionControlService? = nil,
        notificationService: AppNotificationService? = nil
    ) {
        self.controlService = controlService ?? WorkSessionControlService()
        self.notificationService = notificationService ?? AppNotificationService()
    }

    func start() {
        guard fastTickCancellable == nil else { return }

        refresh()

        fastTickCancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.fastTick()
                }
            }

        slowTickCancellable = Timer.publish(every: 120, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
    }

    func stop() {
        fastTickCancellable?.cancel()
        fastTickCancellable = nil
        slowTickCancellable?.cancel()
        slowTickCancellable = nil
    }

    func updateSettings(_ settings: AppSettings) {
        guard self.settings != settings else { return }
        self.settings = settings
        // This class is `@MainActor`-isolated, so any caller
        // (Combine receiveValue, SwiftUI onChange, etc.) is already on
        // the main actor. The extra `Task { @MainActor … }` hop just
        // deferred `refresh()` to the next runloop tick for no
        // benefit — fixed `unowned`/`weak` capture lifetime concerns
        // since the controller outlives every subscriber. Call
        // `refresh()` directly so the next observer sees the new
        // state synchronously.
        refresh()
    }

    func refresh() {
        idleSeconds = Self.currentIdleSeconds()

        do {
            activeSession = try controlService.fetchActiveSession()
            pausedSession = try controlService.fetchPausedSession()
            quickTodos = try controlService.fetchQuickTodos(
                preferredStatusIds: settings.menuBarStatusIds
            )
        } catch {
            lastAutomationMessage = error.localizedDescription
            activeSession = nil
            pausedSession = nil
            quickTodos = []
        }
    }

    func startWork(todoId: String) {
        runAction {
            try controlService.startWork(todoId: todoId)
            lastAutomationMessage = nil
        }
    }

    func stopWork(todoId: String) {
        runAction {
            try controlService.stopWork(todoId: todoId)
            lastAutomationMessage = nil
        }
    }

    func stopActiveWork() {
        runAction {
            try controlService.stopActiveWork()
            lastAutomationMessage = nil
        }
    }

    func pauseActiveWork() {
        runAction {
            try controlService.pauseActiveWork()
            lastAutomationMessage = nil
        }
    }

    func resumePausedWork() {
        runAction {
            try controlService.resumePausedWork()
            lastAutomationMessage = nil
        }
    }

    /// The previous version called `refresh()` in both the success and
    /// failure branches, so a `refresh()` running after an error pushed
    /// state a second time and risked overwriting `lastAutomationMessage`
    /// with the value recomputed inside `refresh()`. A single `defer`
    /// guarantees exactly one refresh on both the success and error paths.
    private func runAction(_ action: () throws -> Void) {
        defer { refresh() }
        do {
            try action()
            hasTriggeredIdleStop = false
        } catch {
            lastAutomationMessage = error.localizedDescription
        }
    }

    /// Fast tick: only updates the idle seconds and triggers the
    /// auto-stop action if needed. Does not touch the DB — it's the
    /// hot path, so it produces zero I/O when there's no active session.
    private func fastTick() {
        idleSeconds = Self.currentIdleSeconds()

        guard settings.idleAutoStopEnabled,
              activeSession != nil,
              idleSeconds >= TimeInterval(settings.idleAutoStopMinutes * 60) else {
            hasTriggeredIdleStop = false
            return
        }

        guard !hasTriggeredIdleStop else { return }

        do {
            let pausedTaskTitle = activeSession?.todoTitle ?? localized("menuBar.header.active", defaultValue: "Aktif çalışma")
            try controlService.pauseActiveWork()
            lastAutomationMessage = String(
                format: localized(
                    "menuBar.message.idlePaused",
                    defaultValue: "“%@” boşta kalma nedeniyle duraklatıldı. İsterseniz devam ettirebilirsiniz."
                ),
                pausedTaskTitle
            )
            notificationService.notifyIdleAutoStop(taskTitle: pausedTaskTitle)
            hasTriggeredIdleStop = true
            // After a pause, sync the UI state from the DB.
            refresh()
        } catch {
            lastAutomationMessage = error.localizedDescription
        }
    }

    /// A raw bitmask value that doesn't map to the `CGEventType` enum
    /// covers every event type with a single `secondsSinceLastEventType`
    /// call. The previous code made 13 separate system calls (one per
    /// event type) and took their `min`.
    ///
    /// `CGEventType.init(rawValue:)` is a failable init that
    /// in practice never fails for `~0` on macOS, but a future SDK
    /// change could flip that. Use a safe fallback to `.null`
    /// (`CGEventType(rawValue: 0)`) which is documented to always
    /// succeed; if it ever did fail we get a graceful zero-mask
    /// behaviour instead of a crash on app launch.
    private static let combinedEventMask: CGEventType =
        CGEventType(rawValue: ~0)
        ?? CGEventType(rawValue: 0)
        ?? .null

    private static func currentIdleSeconds() -> TimeInterval {
        let seconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: combinedEventMask
        )
        return seconds.isFinite && seconds >= 0 ? seconds : 0
    }
}
