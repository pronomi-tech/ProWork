//  MenuBarController.swift
//  ProWork
//  Created by Pronomi.

import AppKit
import SwiftUI
import os

@MainActor
final class MenuBarController: NSObject {
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    /// Feature flag for the right-click context menu (header
    /// + main-window + quit). Gated off by default because there's no
    /// UI to flip it on and the popover already exposes every action;
    /// retained so a future tier can either ship the right-click flow
    /// or delete the helpers (`makeHeaderItem`, `makeActionItem`,
    /// `showContextMenu`) without a separate cleanup pass.
    private let isContextMenuEnabled = false

    // Previously held as weak references, which was
    // safe in steady state (the App scope keeps strong refs) but left a
    // brittle window where a queued event handler could see nil during
    // teardown. These stores live for the entire app lifecycle, so strong
    // references match their actual ownership semantics.
    private var settingsStore: AppSettingsStore?
    private var automationController: WorkAutomationController?
    private var toastStore: ProWorkToastStore?
    /// Required so the popover's active-session duration
    /// ticks while open. Without this the elapsed time was frozen at
    /// the snapshot value when the popover appeared.
    private var clockTicker: ProWorkClockTicker?
    private var openMainWindowAction: (() -> Void)?

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
    }

    func configure(
        settingsStore: AppSettingsStore,
        automationController: WorkAutomationController,
        toastStore: ProWorkToastStore,
        clockTicker: ProWorkClockTicker,
        openMainWindow: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.automationController = automationController
        self.toastStore = toastStore
        self.clockTicker = clockTicker
        openMainWindowAction = openMainWindow
        rebuildPopoverContentIfPossible()
    }

    func updateVisibility(isEnabled: Bool) {
        if isEnabled {
            ensureStatusItem()
            rebuildPopoverContentIfPossible()
        } else {
            popover.performClose(nil)
            removeStatusItem()
        }
    }

    private func ensureStatusItem() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "stopwatch", accessibilityDescription: "ProWork")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleStatusItemInteraction(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusItem = item
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        // Target/action retain the controller via NSStatusBar.
        // NSStatusBar.removeStatusItem releases the item, but explicitly
        // dropping the action wiring first avoids the rare case where the
        // bar process delivers a queued click after our removal call.
        statusItem.button?.target = nil
        statusItem.button?.action = nil
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    /// Each call to this method previously replaced
    /// `popover.contentViewController` with a fresh `NSHostingController`,
    /// throwing away any `@State` the SwiftUI tree had built up between
    /// openings. Build the host once on first call and only update the
    /// environment objects via `rootView` reassignment for subsequent calls
    /// — SwiftUI's diffing keeps the existing state intact.
    private func rebuildPopoverContentIfPossible() {
        guard let settingsStore, let automationController, let toastStore, let clockTicker else {
            // Log the early return so an unconfigured menu bar
            // controller hitting `updateVisibility(isEnabled: true)`
            // before `configure(_:_:_:_:)` no longer fails silently —
            // the bar appears but clicking it would have shown an
            // empty popover.
            let hasSettings = self.settingsStore != nil
            let hasAutomation = self.automationController != nil
            let hasToasts = self.toastStore != nil
            ProWorkLog.app.warning(
                "MenuBarController.rebuildPopoverContentIfPossible: dependencies not configured yet (settingsStore=\(hasSettings, privacy: .public), automation=\(hasAutomation, privacy: .public), toasts=\(hasToasts, privacy: .public)); popover will stay empty until configure() is called."
            )
            return
        }

        let openMainWindow: () -> Void = { [weak self] in
            self?.popover.performClose(nil)
            self?.openMainWindowAction?()
        }

        let rootView = MenuBarQuickTimerView(onOpenMainWindow: openMainWindow)
            .environmentObject(settingsStore)
            .environmentObject(automationController)
            .environmentObject(toastStore)
            // Ticks the active-session duration while the
            // popover is open.
            .environmentObject(clockTicker)

        if let existing = popover.contentViewController as? NSHostingController<AnyView> {
            // SwiftUI compares the new view tree against the old and keeps
            // @State / @StateObject identity stable across this reassignment.
            existing.rootView = AnyView(rootView)
        } else {
            popover.contentViewController = NSHostingController(rootView: AnyView(rootView))
        }
    }

    @objc
    private func handleStatusItemInteraction(_ sender: NSStatusBarButton) {
        switch NSApp.currentEvent?.type {
        case .rightMouseUp:
            guard isContextMenuEnabled else { return }
            showContextMenu(from: sender)
        case .leftMouseUp:
            handleLeftClick(from: sender)
        case nil:
            togglePopover(from: sender)
        default:
            break
        }
    }

    private func handleLeftClick(from button: NSStatusBarButton) {
        // Apple HIG: a single click on the status item toggles the popover.
        // The double-click flow (clickCount==2 conflicted with
        // popover.behavior=.transient) was removed; the "Open main window"
        // action is now a button inside the popover.
        togglePopover(from: button)
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        popover.performClose(nil)

        let menu = NSMenu()
        menu.addItem(makeHeaderItem())
        menu.addItem(.separator())
        menu.addItem(makeActionItem(
            title: localized("menuBar.action.mainWindow", defaultValue: "Ana Ekran"),
            systemImage: "macwindow",
            action: #selector(openMainWindowFromMenu)
        ))
        menu.addItem(makeSpacerItem(height: 12))
        menu.addItem(makeActionItem(
            title: localized("menuBar.action.quit", defaultValue: "Kapat"),
            systemImage: "power",
            action: #selector(quitFromMenu)
        ))

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func makeHeaderItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false

        let view = NSHostingView(
            rootView: MenuBarContextHeaderView(
                title: menuHeaderTitle,
                subtitle: menuHeaderSubtitle
            )
        )
        view.frame = NSRect(x: 0, y: 0, width: 220, height: 62)
        item.view = view
        return item
    }

    private func makeActionItem(
        title: String,
        systemImage: String,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium)
            ]
        )
        item.indentationLevel = 1
        return item
    }

    private func makeSpacerItem(height: CGFloat) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: height))
        item.view = view
        return item
    }

    @objc
    private func openMainWindowFromMenu() {
        NSApp.activate(ignoringOtherApps: true)
        openMainWindowAction?()

        // `openMainWindowAction` calls SwiftUI's `openWindow(id:)`
        // which schedules the window creation asynchronously — when this
        // method runs synchronously the window is not yet in
        // `NSApp.windows`. The `DispatchQueue.main.async` hop lets the
        // window appear before we look it up. Without this, the lookup
        // races and the menu-bar click sometimes leaves the app
        // activated with no key window.
        //
        // Filter by SwiftUI scene identifier instead of the
        // localised title. Window titles change with the active
        // locale, so the previous `$0.title == "ProWork"` check missed
        // the window the moment the user switched UI language.
        DispatchQueue.main.async {
            let mainWindowIdentifier = ProWorkSceneID.mainWindow
            if let window = NSApp.windows.first(where: { window in
                window.className != "NSStatusBarWindow"
                && (window.identifier?.rawValue.hasPrefix(mainWindowIdentifier) ?? false)
            }) {
                window.makeKeyAndOrderFront(nil)
                return
            }
            // SwiftUI 14/15 occasionally renames its window identifiers
            // (e.g. an appended `-AppWindow-1` suffix). Fall back to
            // the first non-status, non-popover window so we still
            // surface *something* rather than failing silently.
            if let window = NSApp.windows.first(where: { window in
                window.className != "NSStatusBarWindow"
                && window.className != "NSPanel"
                && window.canBecomeKey
            }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    // Previously each accessor reached through the
    // optional controller multiple times with separate `?.` chains. Bind
    // once at the top of the computed property so the read is consistent
    // and a future migration to a non-optional reference becomes a
    // one-line change.
    private var menuHeaderTitle: String {
        guard let controller = automationController else { return "ProWork" }
        if controller.activeSession != nil {
            return localized("menuBar.header.active", defaultValue: "Aktif Çalışma")
        }
        if controller.pausedSession != nil {
            return localized("menuBar.header.paused", defaultValue: "Duraklatılmış Çalışma")
        }
        return "ProWork"
    }

    private var menuHeaderSubtitle: String {
        guard let controller = automationController else {
            return localized("menuBar.subtitle.default", defaultValue: "Ana ekranı açabilirsiniz.")
        }
        if let active = controller.activeSession {
            return active.todoTitle
        }
        if let paused = controller.pausedSession {
            return paused.todoTitle
        }
        return localized("menuBar.subtitle.default", defaultValue: "Ana ekranı açabilirsiniz.")
    }

    @objc
    private func quitFromMenu() {
        NSApp.terminate(nil)
    }
}

private struct MenuBarContextHeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "stopwatch.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 220, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
