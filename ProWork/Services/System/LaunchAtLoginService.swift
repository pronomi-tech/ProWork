//  LaunchAtLoginService.swift
//  ProWork
//   Created by Pronomi.

import Foundation
import ServiceManagement

enum LaunchAtLoginError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return ProWorkLocalizer.shared.string(
                "launchAtLogin.error.unsupported",
                defaultValue: "Bu macOS sürümünde açılışta başlatma desteklenmiyor."
            )
        }
    }
}

/// When relaying `LaunchAtLoginService` status to the UI, `enabled` and `requiresApproval`
/// must look different. The previous `Bool`-returning API merged the two and
/// created a state where the user was shown "on" but the app didn't actually
/// launch at login.
enum LaunchAtLoginState: Equatable {
    /// Actually launches at login.
    case enabled
    /// Registered but macOS is awaiting user approval; doesn't launch at login
    /// until the Login Items settings are opened.
    case requiresApproval
    /// Disabled (not registered) or unknown state.
    case disabled
}

final class LaunchAtLoginService {
    var isSupported: Bool {
        if #available(macOS 13.0, *) {
            return true
        }

        return false
    }

    /// Current state. The UI can render three distinct buckets — "On",
    /// "Awaiting Approval", or "Off" — based on this enum.
    func currentState() -> LaunchAtLoginState {
        guard #available(macOS 13.0, *) else {
            return .disabled
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        default:
            return .disabled
        }
    }

    /// For bool callers like a `Toggle`, only `.enabled` is treated as
    /// truly "on" — a registration awaiting approval is not surfaced
    /// to the user as "on".
    func currentEnabled() -> Bool {
        currentState() == .enabled
    }

    /// When `currentState() == .requiresApproval`, call this helper to
    /// route the user to the Login Items screen.
    @available(macOS 13.0, *)
    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw LaunchAtLoginError.unsupported
        }

        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            try SMAppService.mainApp.unregister()
        }
    }
}
