//  ProWorkLog.swift
//  ProWork
//  Created by Pronomi.
//  Shared os.Logger instances used across the app.
//  The previous `print(...)` calls were problematic for a financial app:
//    - PII (user path, customer name embedded in error messages, etc.)
//      hit Console.app as plain strings.
//    - Output wasn't disabled even in production builds.
//    - Audit/debug filtering by category wasn't possible.
//  With `Logger`:
//    - `privacy: .private` redacts sensitive fields.
//    - Console.app can filter by `subsystem` + `category`.
//    - Default log level is optimised in release builds.

import Foundation
import os

// The project uses SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so we mark
// the enum members `nonisolated` explicitly. Otherwise `Task.detached`,
// repository threads, and other nonisolated contexts can't log (Swift 6 error).
// `os.Logger` is Sendable, so it's safe from any context.
enum ProWorkLog {
    nonisolated static let subsystem = "com.pronomi.prowork"

    nonisolated static let app = Logger(subsystem: subsystem, category: "app")
    nonisolated static let database = Logger(subsystem: subsystem, category: "database")
    nonisolated static let billing = Logger(subsystem: subsystem, category: "billing")
    nonisolated static let sync = Logger(subsystem: subsystem, category: "sync")
    nonisolated static let settings = Logger(subsystem: subsystem, category: "settings")
    nonisolated static let export = Logger(subsystem: subsystem, category: "export")
}
