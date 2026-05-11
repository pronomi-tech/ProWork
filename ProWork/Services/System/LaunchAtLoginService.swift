//
//  LaunchAtLoginService.swift
//  ProWork
//
//   Created by Pronomi.
//

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

final class LaunchAtLoginService {
    var isSupported: Bool {
        if #available(macOS 13.0, *) {
            return true
        }

        return false
    }

    func currentEnabled() -> Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }

        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
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
