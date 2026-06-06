//  AppNotificationService.swift
//  ProWork
//   Created by Pronomi.

import Foundation
@preconcurrency import UserNotifications

/// `@MainActor` isolation wasn't required — the class talks to
/// UNUserNotificationCenter via async APIs, the permission flow already
/// `await`s inside, and any UI touch is left to the caller. We mark
/// it `nonisolated` so the caller can trigger it freely from background
/// threads too.
final class AppNotificationService {

    /// The "Enable notifications" flow on the Settings screen calls this,
    /// so the permission dialog appears at a moment the user deliberately
    /// opened, not as a surprise on the first idle.
    /// Returns: `true` → permission granted, `false` → denied / undetermined.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func notifyIdleAutoStop(taskTitle: String) {
        let body = String(
            format: ProWorkLocalizer.shared.string(
                "notification.idleAutoStop",
                defaultValue: "“%@” boşta kalma nedeniyle otomatik duraklatıldı."
            ),
            taskTitle
        )

        deliver(body: body, identifier: "prowork-idle-auto-stop")
    }

    /// Depending on the current authorization, either sends a system
    /// notification via `UNUserNotificationCenter` or shows an in-app
    /// fallback toast through `ProWorkToastStore`. Previously the user
    /// got no feedback at all when status was `denied`.
    private func deliver(body: String, identifier: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                let content = UNMutableNotificationContent()
                content.title = "ProWork"
                content.body = body
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: nil
                )
                do {
                    try await center.add(request)
                } catch {
                    showInAppFallback(body: body)
                }
            case .denied:
                // User denied permission — show an in-app toast instead of staying silent.
                showInAppFallback(body: body)
            case .notDetermined:
                // Permission hasn't been asked yet. We prefer the fallback
                // toast so an idle-time surprise dialog doesn't appear;
                // once the user calls `requestAuthorizationIfNeeded()`
                // from the Settings page, subsequent notifications are
                // delivered through the system.
                showInAppFallback(body: body)
            @unknown default:
                showInAppFallback(body: body)
            }
        }
    }

    private func showInAppFallback(body: String) {
        Task { @MainActor in
            ProWorkToastStore.shared.show(body, style: .info)
        }
    }
}
