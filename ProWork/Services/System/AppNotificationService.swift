//
//  AppNotificationService.swift
//  ProWork
//
//   Created by Pronomi.
//

import Foundation
@preconcurrency import UserNotifications

@MainActor
final class AppNotificationService {
    func notifyIdleAutoStop(taskTitle: String) {
        let body = String(
            format: ProWorkLocalizer.shared.string(
                "notification.idleAutoStop",
                defaultValue: "“%@” boşta kalma nedeniyle otomatik duraklatıldı."
            ),
            taskTitle
        )

        Task {
            let content = UNMutableNotificationContent()
            content.title = "ProWork"
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "prowork-idle-auto-stop",
                content: content,
                trigger: nil
            )

            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                try? await center.add(request)
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                guard granted else { return }
                try? await center.add(request)
            default:
                return
            }
        }
    }
}
