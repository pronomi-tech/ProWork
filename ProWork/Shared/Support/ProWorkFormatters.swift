//
//  ProWorkFormatters.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

enum ProWorkFormatters {
    static func durationHHmm(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60

        return String(format: "%02d:%02d", hours, minutes)
    }

    static func durationHM(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)s \(minutes)dk"
        }

        return "\(minutes)dk"
    }
}
