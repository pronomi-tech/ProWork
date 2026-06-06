//  ProWorkApp.swift
//  ProWork
//  Created by Pronomi.

import AppKit
import SwiftUI

enum ProWorkSceneID {
    static let mainWindow = "main-window"
}

/// Class-backed holder used to capture a NotificationCenter observer token by
/// reference inside its own closure, even when the host is a struct. See the
/// `applyInitialPresentationIfNeeded` use site.
private final class ObserverTokenHolder {
    var token: NSObjectProtocol?
}

final class ProWorkAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct ProWorkApp: App {
    @NSApplicationDelegateAdaptor(ProWorkAppDelegate.self) private var appDelegate
    @StateObject private var settingsStore = AppSettingsStore()
    @StateObject private var sessionController = DatabaseSessionController()
    @StateObject private var automationController = WorkAutomationController()
    @StateObject private var clockTicker = ProWorkClockTicker()
    @State private var menuBarController = MenuBarController()

    // @StateObject is designed to own a fresh instance
    // per view lifetime; pairing it with a shared singleton (`.shared`)
    // misuses the property wrapper because SwiftUI can in theory call the
    // autoclosure more than once and would then take ownership of an object
    // it didn't create. Hold the singletons as plain `let` references and
    // inject them via `.environmentObject` — they live for the app's
    // process lifetime so no wrapper is needed.
    private let toastStore = ProWorkToastStore.shared
    private let services = AppServices.shared

    var body: some Scene {
        Window("ProWork", id: ProWorkSceneID.mainWindow) {
            MainWindowSceneView(menuBarController: menuBarController)
                .environmentObject(settingsStore)
                .environmentObject(sessionController)
                .environmentObject(automationController)
                .environmentObject(toastStore)
                .environmentObject(services)
                .environmentObject(clockTicker)
                .environment(\.locale, settingsStore.locale)
                .proWorkFontScale(settingsStore.settings.fontSize.scale)
                .proWorkToastOverlay()
        }
    }
}

private struct MainWindowSceneView: View {
    let menuBarController: MenuBarController

    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @EnvironmentObject private var sessionController: DatabaseSessionController
    @EnvironmentObject private var automationController: WorkAutomationController
    @EnvironmentObject private var toastStore: ProWorkToastStore
    /// Forwarded into the menu-bar popover so the quick
    /// timer renders a live duration while open.
    @EnvironmentObject private var clockTicker: ProWorkClockTicker

    // Tracks the database URL bootstrap last ran for. A `nil` value means
    // settings/automation haven't been initialised yet for the current
    // session; any time `sessionController.phase` becomes `.ready` with a
    // *different* URL, bootstrap re-runs against the new DB. K11 already
    // forces a relaunch when switching databases mid-session, but this
    // also defends against any future code path that lands on a new URL
    // without restarting.
    @State private var settingsLoadedForDatabaseURL: URL?
    @State private var hasAppliedInitialPresentation = false

    var body: some View {
        Group {
            switch sessionController.phase {
            case .launching:
                ProgressView(settingsStore.localized("app.loading.database", defaultValue: "Veri dosyası hazırlanıyor…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .needsSelection(let message):
                DatabaseSetupView(message: message)
            case .ready:
                VStack(spacing: 0) {
                    if let warning = sessionController.durabilityWarning {
                        DatabaseDurabilityBanner(
                            message: warning,
                            onRelocate: { sessionController.relocateDatabase() }
                        )
                    }
                    ContentView()
                        .environmentObject(settingsStore)
                        .environmentObject(automationController)
                }
            }
        }
        .environmentObject(settingsStore)
        .environmentObject(sessionController)
        .sheet(item: $sessionController.pendingDatabaseSelection) { selection in
            DatabaseFilePickerSheet(
                selection: selection,
                onPick: { sessionController.confirmDatabaseSelection($0) },
                onCancel: { sessionController.cancelDatabaseSelection() }
            )
            .environmentObject(settingsStore)
        }
        .onAppear {
            sessionController.bootstrapIfNeeded()
            bootstrapIfNeeded()
            syncMenuBar()
        }
        .onChange(of: sessionController.phase) { _, _ in
            bootstrapIfNeeded()
            syncMenuBar()
        }
        .onChange(of: settingsStore.settings) { _, newValue in
            Task { @MainActor in
                automationController.updateSettings(newValue)
            }
            syncMenuBar()
        }
    }

    private func bootstrapIfNeeded() {
        guard case .ready(let url) = sessionController.phase else { return }
        guard settingsLoadedForDatabaseURL != url else { return }

        settingsStore.load()
        // Previously this dispatched updateSettings through
        // `Task { @MainActor in ... }`, which adds an async hop even though
        // bootstrapIfNeeded() is already MainActor-isolated. Call directly.
        automationController.updateSettings(settingsStore.settings)
        automationController.start()

        settingsLoadedForDatabaseURL = url
        applyInitialPresentationIfNeeded()
    }

    /// The previous 0.25s `asyncAfter` was a "wait until
    /// SwiftUI has actually instantiated the window" guess and caused a
    /// visible flash. Observe `NSWindow.didBecomeVisibleNotification`
    /// instead: as soon as the first eligible window goes visible we
    /// immediately `orderOut`, removing the flash without a guessed delay.
    private func applyInitialPresentationIfNeeded() {
        guard !hasAppliedInitialPresentation else { return }
        hasAppliedInitialPresentation = true

        guard settingsStore.settings.menuBarEnabled,
              !settingsStore.settings.openMainWindowOnLaunch else {
            return
        }

        // If a window is already visible, hide it on the next runloop tick
        // (RunLoop.main.perform schedules on the current loop's next tick
        // rather than a wall-clock delay).
        if let window = NSApp.windows.first(where: \.isVisible) {
            RunLoop.main.perform { window.orderOut(nil) }
            return
        }

        // Otherwise wait for the first window to become visible.
        // the previous version stored the returned
        // token into a local optional that was assigned *after*
        // addObserver returned. The closure body then read that local —
        // if the notification fired before the assignment completed
        // (theoretically possible if another notification path were ever
        // posted synchronously) the closure would observe nil and the
        // observer would leak forever. Capture a small class-backed
        // holder strongly inside the closure so the token slot is
        // reachable regardless of registration ordering.
        // Note: NSWindow has no `didBecomeVisibleNotification`. Use the
        // window key-status notification which fires when the first
        // opened window becomes active — close enough for the "hide
        // launch flash" use case the original comment described.
        let holder = ObserverTokenHolder()
        holder.token = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [holder] notification in
            guard let window = notification.object as? NSWindow else { return }
            // Only hide the actual main scene window. The
            // didBecomeKeyNotification fires for every window that
            // becomes key (about panel, settings sheets, status bar
            // popovers, …), so the previous unfiltered hide would
            // occasionally orderOut a freshly-opened dialog and leave
            // the user staring at no UI. Identify the window by the
            // SwiftUI scene identifier that `Window("…", id: …)`
            // installs on the underlying NSWindow.
            let mainWindowIdentifier = ProWorkSceneID.mainWindow
            let isMainScene = (window.identifier?.rawValue.hasPrefix(mainWindowIdentifier) ?? false)
            guard isMainScene else { return }
            window.orderOut(nil)
            if let token = holder.token {
                NotificationCenter.default.removeObserver(token)
                holder.token = nil
            }
        }
    }

    private func syncMenuBar() {
        menuBarController.configure(
            settingsStore: settingsStore,
            automationController: automationController,
            toastStore: toastStore,
            clockTicker: clockTicker
        ) {
            openWindow(id: ProWorkSceneID.mainWindow)
        }

        let isReady: Bool
        if case .ready = sessionController.phase {
            isReady = true
        } else {
            isReady = false
        }

        menuBarController.updateVisibility(
            isEnabled: isReady && settingsStore.settings.menuBarEnabled
        )
    }
}
