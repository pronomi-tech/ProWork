//  Holiday.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Holiday scope.
enum HolidayScope: String, CaseIterable, Identifiable, Hashable {
    case global   // organization-wide
    case customer // customer-specific override

    var id: String { rawValue }
}

/// Public/half-day holiday. If half-day, the holiday begins after the given cutoff time.
struct Holiday: Identifiable, Hashable {
    let id: String
    var scope: HolidayScope
    var customerId: String?
    /// Date in "yyyy-MM-dd" format.
    var dateString: String
    var name: String
    var isHalfDay: Bool
    var halfDayCutoff: TimeOfDay?
    var isActive: Bool

    var organizationId: String
    var createdByUserId: String?
    var updatedByUserId: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var rowVersion: Int
    var syncStatus: SyncStatus
    var lastSyncedAt: Date?
    var originDeviceId: String?

    init(
        id: String = UUID().uuidString,
        scope: HolidayScope = .global,
        customerId: String? = nil,
        dateString: String,
        name: String,
        isHalfDay: Bool = false,
        halfDayCutoff: TimeOfDay? = nil,
        isActive: Bool = true,
        organizationId: String = BuiltInOrganizationId.default,
        createdByUserId: String? = BuiltInUserId.defaultOwner,
        updatedByUserId: String? = BuiltInUserId.defaultOwner,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        rowVersion: Int = 0,
        syncStatus: SyncStatus = .local,
        lastSyncedAt: Date? = nil,
        originDeviceId: String? = DeviceIdentity.current
    ) {
        self.id = id
        self.scope = scope
        self.customerId = customerId
        self.dateString = dateString
        self.name = name
        self.isHalfDay = isHalfDay
        self.halfDayCutoff = halfDayCutoff
        self.isActive = isActive
        self.organizationId = organizationId
        self.createdByUserId = createdByUserId
        self.updatedByUserId = updatedByUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.rowVersion = rowVersion
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
        self.originDeviceId = originDeviceId
    }
}

extension Holiday {
    /// holiday strings are interpreted in the application's
    /// canonical billing timezone (`AppCalendar.istanbul`) rather than a
    /// hardcoded `Europe/Istanbul` literal. When the app gains support for
    /// other tenants / locales this becomes a single line change.
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppCalendar.istanbul.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var date: Date? {
        Self.dateFormatter.date(from: dateString)
    }

    var meta: RecordMetadata {
        RecordMetadata(
            organizationId: organizationId,
            createdByUserId: createdByUserId,
            updatedByUserId: updatedByUserId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowVersion: rowVersion,
            syncStatus: syncStatus,
            lastSyncedAt: lastSyncedAt,
            originDeviceId: originDeviceId
        )
    }

    init(
        id: String = UUID().uuidString,
        scope: HolidayScope = .global,
        customerId: String? = nil,
        dateString: String,
        name: String,
        isHalfDay: Bool = false,
        halfDayCutoff: TimeOfDay? = nil,
        isActive: Bool = true,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            scope: scope,
            customerId: customerId,
            dateString: dateString,
            name: name,
            isHalfDay: isHalfDay,
            halfDayCutoff: halfDayCutoff,
            isActive: isActive,
            organizationId: meta.organizationId,
            createdByUserId: meta.createdByUserId,
            updatedByUserId: meta.updatedByUserId,
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            deletedAt: meta.deletedAt,
            rowVersion: meta.rowVersion,
            syncStatus: meta.syncStatus,
            lastSyncedAt: meta.lastSyncedAt,
            originDeviceId: meta.originDeviceId
        )
    }
}
