//
//  IslamicHolidayBootstrap.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Migration001'in hardcoded ettiği 2024-2030 dini bayramlar bitince
//  uygulamanın tatil tablosunda boşluk kalıyordu. Bu servis açılışta
//  generator'ı çağırıp eksik yılları doldurur. Mevcut satırlara
//  dokunmaz — kullanıcı UI'dan düzenlemiş olabilir.
//

import Foundation

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

    /// `currentYear..currentYear+yearsAhead` aralığında dini bayram + arefe
    /// satırlarını ekler. Aynı tarihte aynı isimle bir satır zaten varsa
    /// (örn. Migration001 seed'i veya kullanıcı eklemesi) dokunmaz.
    func ensurePopulated(
        currentYear: Int,
        yearsAhead: Int = 5,
        now: Date = Date()
    ) throws {
        let existing = try holidayRepository.fetchAll(
            organizationId: organizationId,
            includingInactive: true
        )

        // (dateString, name) tuple'ını fingerprint olarak kullanıyoruz; aynı
        // tarihte farklı bir isimle resmi tatil olabilir (örn. 19 Mayıs ile
        // Kurban Bayramı çakışması — review Madde 9'da bahsedilen senaryo).
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
    }

    private static func fingerprint(date: String, name: String) -> String {
        "\(date)|\(name)"
    }
}
