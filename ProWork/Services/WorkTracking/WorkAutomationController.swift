//
//  WorkAutomationController.swift
//  ProWork
//
//   Created by Pronomi.
//

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
    private let notificationService = AppNotificationService()
    private var settings: AppSettings = .defaults
    private var timerCancellable: AnyCancellable?
    private var hasTriggeredIdleStop = false

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    init(controlService: WorkSessionControlService? = nil) {
        self.controlService = controlService ?? WorkSessionControlService()
    }

    func start() {
        guard timerCancellable == nil else { return }

        refresh()

        timerCancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.tick()
                }
            }
    }

    func updateSettings(_ settings: AppSettings) {
        guard self.settings != settings else { return }
        self.settings = settings
        Task { @MainActor [weak self] in
            self?.refresh()
        }
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

    private func runAction(_ action: () throws -> Void) {
        do {
            try action()
            hasTriggeredIdleStop = false
            refresh()
        } catch {
            lastAutomationMessage = error.localizedDescription
            refresh()
        }
    }

    private func tick() {
        idleSeconds = Self.currentIdleSeconds()

        if settings.idleAutoStopEnabled,
           activeSession != nil,
           idleSeconds >= TimeInterval(settings.idleAutoStopMinutes * 60) {
            if !hasTriggeredIdleStop {
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
                } catch {
                    lastAutomationMessage = error.localizedDescription
                }
            }
        } else {
            hasTriggeredIdleStop = false
        }

        refresh()
    }

    private static func currentIdleSeconds() -> TimeInterval {
        let eventTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown,
            .leftMouseUp,
            .leftMouseDragged,
            .rightMouseDown,
            .rightMouseUp,
            .rightMouseDragged,
            .otherMouseDown,
            .otherMouseUp,
            .otherMouseDragged,
            .scrollWheel,
            .keyDown,
            .keyUp
        ]

        let samples = eventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .filter { $0.isFinite && $0 >= 0 }

        return samples.min() ?? 0
    }
}
