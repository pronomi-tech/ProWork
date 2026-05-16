//
//  ProWorkApp.swift
//  ProWork
//
//  Created by Pronomi.
//

import AppKit
import SwiftUI

enum ProWorkSceneID {
    static let mainWindow = "main-window"
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
    @StateObject private var toastStore = ProWorkToastStore.shared
    @StateObject private var services = AppServices.shared
    @State private var menuBarController = MenuBarController()

    var body: some Scene {
        Window("ProWork", id: ProWorkSceneID.mainWindow) {
            MainWindowSceneView(menuBarController: menuBarController)
                .environmentObject(settingsStore)
                .environmentObject(sessionController)
                .environmentObject(automationController)
                .environmentObject(toastStore)
                .environmentObject(services)
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

    @State private var hasLoadedSettings = false
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
                ContentView()
                    .environmentObject(settingsStore)
                    .environmentObject(automationController)
            }
        }
        .environmentObject(settingsStore)
        .environmentObject(sessionController)
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
        guard case .ready = sessionController.phase else { return }
        guard !hasLoadedSettings else { return }

        settingsStore.load()
        Task { @MainActor in
            automationController.updateSettings(settingsStore.settings)
        }
        automationController.start()

        hasLoadedSettings = true
        applyInitialPresentationIfNeeded()
    }

    private func applyInitialPresentationIfNeeded() {
        guard !hasAppliedInitialPresentation else { return }
        hasAppliedInitialPresentation = true

        guard settingsStore.settings.menuBarEnabled,
              !settingsStore.settings.openMainWindowOnLaunch else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if let window = NSApp.windows.first(where: \.isVisible) ?? NSApp.keyWindow ?? NSApp.mainWindow {
                window.orderOut(nil)
            }
        }
    }

    private func syncMenuBar() {
        menuBarController.configure(
            settingsStore: settingsStore,
            automationController: automationController,
            toastStore: toastStore
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
