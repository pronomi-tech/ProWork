//
//  MenuBarController.swift
//  ProWork
//
//  Created by Pronomi.
//

import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var pendingSingleClick: DispatchWorkItem?
    private let isContextMenuEnabled = false
    private let singleClickDelay: TimeInterval = 0.18

    private weak var settingsStore: AppSettingsStore?
    private weak var automationController: WorkAutomationController?
    private weak var toastStore: ProWorkToastStore?
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
        openMainWindow: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.automationController = automationController
        self.toastStore = toastStore
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
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func rebuildPopoverContentIfPossible() {
        guard let settingsStore, let automationController, let toastStore else { return }

        popover.contentViewController = NSHostingController(
            rootView: MenuBarQuickTimerView()
                .environmentObject(settingsStore)
                .environmentObject(automationController)
                .environmentObject(toastStore)
        )
    }

    @objc
    private func handleStatusItemInteraction(_ sender: NSStatusBarButton) {
        switch NSApp.currentEvent?.type {
        case .rightMouseUp:
            cancelPendingSingleClick()
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
        if NSApp.currentEvent?.clickCount == 2 {
            cancelPendingSingleClick()
            popover.performClose(nil)
            openMainWindowFromMenu()
            return
        }

        let workItem = DispatchWorkItem { [weak self, weak button] in
            guard let self, let button else { return }
            self.togglePopover(from: button)
        }

        pendingSingleClick = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + singleClickDelay,
            execute: workItem
        )
    }

    private func cancelPendingSingleClick() {
        pendingSingleClick?.cancel()
        pendingSingleClick = nil
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

        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: {
                $0.title == "ProWork" && $0.className != "NSStatusBarWindow"
            }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private var menuHeaderTitle: String {
        if automationController?.activeSession != nil {
            return localized("menuBar.header.active", defaultValue: "Aktif Çalışma")
        }

        if automationController?.pausedSession != nil {
            return localized("menuBar.header.paused", defaultValue: "Duraklatılmış Çalışma")
        }

        return "ProWork"
    }

    private var menuHeaderSubtitle: String {
        if let active = automationController?.activeSession {
            return active.todoTitle
        }

        if let paused = automationController?.pausedSession {
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
