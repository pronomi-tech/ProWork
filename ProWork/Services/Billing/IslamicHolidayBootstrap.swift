//  IslamicHolidayBootstrap.swift
//  ProWork
//  Created by Pronomi.
//  Once the 2024-2030 religious holidays hardcoded by Migration001 ran out,
//  the app's holiday table left a gap. This service runs at startup and
//  calls the generator to fill in the missing years. It does not touch
//  existing rows — the user may have edited them via the UI.

import Foundation
import os

@MainActor
final class IslamicHolidayBootstrap {
    private let holidayRepository: HolidayRepository
    private let organizationId: String

    init(
        holidayRepository: HolidayRepository? = nil,
        organizationId: String? = nil
    ) {
        self.holidayRepository = holidayRepository ?? HolidayRepository()
        self.organizationId = organizationId ?? BuiltInOrganizationId.default
    }

    /// Inserts religious-holiday + eve rows for the range
    /// `currentYear..currentYear+yearsAhead`. If a row with the same date
    /// and name already exists (e.g. a Migration001 seed or a user entry)
    /// it is left untouched.
    func ensurePopulated(
        currentYear: Int,
        yearsAhead: Int = BillingDefaults.islamicHolidayYearsAhead,
        now: Date = Date()
    ) throws {
        let existing = try holidayRepository.fetchAll(
            organizationId: organizationId,
            includingInactive: true
        )

        // We use the (dateString, name) tuple as the fingerprint; the same
        // date can carry a different public holiday under a different name
        // (e.g. 19 May colliding with Eid al-Adha — the scenario flagged
        // in review item 9).
        var fingerprints: Set<String> = []
        for holiday in existing where holiday.scope == .global {
            fingerprints.insert(Self.fingerprint(date: holiday.dateString, name: holiday.name))
        }

        for offset in 0...yearsAhead {
            let year = currentYear + offset
            let generated = TurkishIslamicHolidayGenerator.holidays(
                forGregorianYear: year,
                organizationId: organizationId,
                now: now
            )

            for holiday in generated {
                let key = Self.fingerprint(date: holiday.dateString, name: holiday.name)
                guard !fingerprints.contains(key) else { continue }

                try holidayRepository.insert(holiday)
                fingerprints.insert(key)
            }
        }

        // Y7: Check whether generated dates exceed the manually-verified
        // horizon. When Diyanet publishes the calendar for the next year,
        // `verifiedThroughGregorianYear` must be bumped (and a
        // `diyanetOverrides` row added if needed) — otherwise past years
        // stay correct while future years can drift by 1-2 days.
        let nextHorizon = currentYear + yearsAhead
        if nextHorizon > TurkishIslamicHolidayGenerator.verifiedThroughGregorianYear {
            ProWorkLog.app.warning(
                "Islamic holiday generator: \(nextHorizon - TurkishIslamicHolidayGenerator.verifiedThroughGregorianYear, privacy: .public) year(s) past the verified-through-\(TurkishIslamicHolidayGenerator.verifiedThroughGregorianYear, privacy: .public) cutoff. Compare with Diyanet's official calendar; add `DiyanetHolidayOverride` rows for any mismatches and bump `verifiedThroughGregorianYear`."
            )
        }
    }

    private static func fingerprint(date: String, name: String) -> String {
        "\(date)|\(name)"
    }
}
