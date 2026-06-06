//  DeviceIdentity.swift
//  ProWork
//  Created by Pronomi.
//  Per-install device identifier used to populate `RecordMetadata.originDeviceId`.
//  Generated once and persisted in UserDefaults so that future multi-device sync
//  can attribute every row to the device that produced it.

import Foundation

enum DeviceIdentity {
    private static let defaultsKey = "com.pronomi.prowork.deviceIdentifier"

    /// Stable, per-install device id. Generated lazily on first read and cached.
    /// macOS `IOPlatformUUID` would also work but requires entitlements and
    /// returns the same value for users who reinstall — a UserDefaults UUID
    /// is intentionally per-install so a reinstall yields a fresh origin.
    static let current: String = {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: defaultsKey)
        return generated
    }()
}
