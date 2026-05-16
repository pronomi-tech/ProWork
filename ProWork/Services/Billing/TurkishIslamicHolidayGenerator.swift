//
//  TurkishIslamicHolidayGenerator.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Türkiye'deki dini bayramların (Ramazan & Kurban) ve arefelerinin miladi
//  tarihlerini çalışma anında hesaplar. Daha önce Migration001 içinde 2024-2030
//  arası tarihler tek tek hardcoded'di; bu yöntem 2031 sonrası için her yıl
//  manuel güncelleme gerektiriyordu.
//
//  Hesap yöntemi:
//    1. Bayramın hicri datum'u (Şevval 1 = Ramazan Bayramı, Zilhicce 10 =
//       Kurban Bayramı) sabit.
//    2. `Calendar(identifier: .islamicCivil)` ile o yılın miladi karşılığı
//       hesaplanır. Foundation'ın dört Islamic varyantını test ettik;
//       Diyanet'in 2024-2030 açıklamalarına en yakını `islamicCivil`'di
//       (2025'te birebir, sonraki yıllar ekseriyetle 1 gün geride).
//    3. Block bazlı offset override mekanizması: Diyanet bazı yıllarda kendi
//       astronomik hesabıyla 1-2 gün ayrışabiliyor. Override eklendiğinde
//       **tüm bayramı + arefesini** birlikte kaydırır; her günü ayrı ayrı
//       override etmek gerekmez. Tek satır = tüm bayram.
//    4. Apple/ICU'da Türkiye Diyanet'in resmi takvimi için ayrı bir
//       calendar identifier yok; tam doğruluk için Diyanet'in yıllık
//       açıklamasına göre override eklenmesi beklenir.
//

import Foundation

enum TurkishIslamicHolidayBlockId: String {
    case ramazan
    case kurban
}

struct TurkishIslamicHolidayBlock {
    let id: TurkishIslamicHolidayBlockId
    /// Hicri ay numarası: Şevval = 10 (Ramazan Bayramı 1. günü), Zilhicce = 12
    /// (Kurban Bayramı 1. günü).
    let hijriMonth: Int
    /// Bayramın 1. gününün hicri ay içindeki indeksi.
    let hijriDayOfFirstBayram: Int
    /// Bayramın gün sayısı (Ramazan 3, Kurban 4).
    let bayramDayCount: Int
    /// Arefe ismi.
    let arefeName: String
    /// Bayram ismi (her gün için "1. Gün", "2. Gün" eklenir).
    let bayramName: String
}

extension TurkishIslamicHolidayBlock {
    static let ramazan = TurkishIslamicHolidayBlock(
        id: .ramazan,
        hijriMonth: 10,                // Şevval
        hijriDayOfFirstBayram: 1,
        bayramDayCount: 3,
        arefeName: "Ramazan Bayramı Arifesi",
        bayramName: "Ramazan Bayramı"
    )

    static let kurban = TurkishIslamicHolidayBlock(
        id: .kurban,
        hijriMonth: 12,                // Zilhicce
        hijriDayOfFirstBayram: 10,
        bayramDayCount: 4,
        arefeName: "Kurban Bayramı Arifesi",
        bayramName: "Kurban Bayramı"
    )

    static let allBlocks: [TurkishIslamicHolidayBlock] = [.ramazan, .kurban]
}

/// Diyanet'in açıkladığı tarih UmmAlQura ile farklılık gösteren yıllar için
/// override. Override **block bazlı** çalışır: tek bir satır bayramın tüm
/// günlerini + arefesini topluca kaydırır.
struct DiyanetHolidayOverride: Hashable {
    let gregorianYear: Int
    let blockId: TurkishIslamicHolidayBlockId
    /// İşaretli kayma. -1 = bir gün geriye, +1 = bir gün ileriye.
    let dayShift: Int
}

enum TurkishIslamicHolidayGenerator {
    /// Diyanet vs. UmmAlQura ayrışmalarının manuel düzeltme listesi.
    /// Şimdilik boş — gerektikçe (Diyanet açıklaması farklı çıkarsa) satır
    /// eklenir. Format: `(yıl, block, gün kayması)`.
    static let diyanetOverrides: [DiyanetHolidayOverride] = []

    /// Belirtilen miladi yıl içinde başlayan Ramazan & Kurban bayramları için
    /// arefe + gün gün `Holiday` satırları üretir. UI / API üzerinden zaten
    /// eklenmiş tarihler varsa caller (HolidayBootstrap) tekrar yazmamalı.
    static func holidays(
        forGregorianYear year: Int,
        organizationId: String = BuiltInOrganizationId.default,
        now: Date = Date()
    ) -> [Holiday] {
        var result: [Holiday] = []

        for block in TurkishIslamicHolidayBlock.allBlocks {
            guard let bayramStart = gregorianStartOfBayram(
                block: block,
                gregorianYear: year
            ) else {
                continue
            }

            let shift = diyanetOverrides.first {
                $0.gregorianYear == year && $0.blockId == block.id
            }?.dayShift ?? 0

            guard let shiftedStart = AppCalendar.istanbul.date(
                byAdding: .day,
                value: shift,
                to: bayramStart
            ) else {
                continue
            }

            // Arefe — bayramın 1. gününün bir önceki günü. Yarım gün.
            if let arefeDate = AppCalendar.istanbul.date(byAdding: .day, value: -1, to: shiftedStart) {
                result.append(makeHoliday(
                    date: arefeDate,
                    name: block.arefeName,
                    isHalfDay: true,
                    organizationId: organizationId,
                    now: now
                ))
            }

            // Bayram günleri — tam gün.
            for dayIndex in 0..<block.bayramDayCount {
                guard let date = AppCalendar.istanbul.date(
                    byAdding: .day,
                    value: dayIndex,
                    to: shiftedStart
                ) else { continue }

                let name = "\(block.bayramName) \(dayIndex + 1). Günü"
                result.append(makeHoliday(
                    date: date,
                    name: name,
                    isHalfDay: false,
                    organizationId: organizationId,
                    now: now
                ))
            }
        }

        return result
    }

    /// Verilen miladi yıl içine düşen bayram başlangıcının miladi tarihini
    /// `islamicUmmAlQura` ile bulur. Hicri yıl miladi yıldan ~622 yıl
    /// küçüktür ve her yıl ~11 gün geriye kayar; bu yüzden bir miladi yıl
    /// içinde aynı bayram **iki kez** veya **hiç** geçebilir. İki olası
    /// hicri yıl adayını deneyip, miladi yılı eşleşeni döndürüyoruz.
    private static func gregorianStartOfBayram(
        block: TurkishIslamicHolidayBlock,
        gregorianYear: Int
    ) -> Date? {
        let islamic = Calendar(identifier: .islamicCivil)

        // Hedef yılın 1 Ocak'ında hangi hicri yıldayız?
        var components = DateComponents()
        components.year = gregorianYear
        components.month = 1
        components.day = 1
        guard let janFirst = AppCalendar.istanbul.date(from: components) else {
            return nil
        }
        let hijriYearAtJanFirst = islamic.component(.year, from: janFirst)

        // Hicri yıl miladi içinde başlayıp bitebileceği için bu ve sonraki
        // hicri yılı dene (Kurban Bayramı Zilhicce 10 — hicri yılın sonuna
        // yakın; o yıla göre miladi karşılığı uzayabiliyor).
        for hijriYear in [hijriYearAtJanFirst, hijriYearAtJanFirst + 1] {
            var hijriComponents = DateComponents()
            hijriComponents.year = hijriYear
            hijriComponents.month = block.hijriMonth
            hijriComponents.day = block.hijriDayOfFirstBayram

            guard let candidate = islamic.date(from: hijriComponents) else {
                continue
            }

            if AppCalendar.istanbul.component(.year, from: candidate) == gregorianYear {
                // Günün başlangıcına normalize et — ileride day offset eklerken
                // saat farkı sürüklenmesin.
                return AppCalendar.istanbul.startOfDay(for: candidate)
            }
        }

        return nil
    }

    private static func makeHoliday(
        date: Date,
        name: String,
        isHalfDay: Bool,
        organizationId: String,
        now: Date
    ) -> Holiday {
        let dateString = AppDateFormatters.sqliteDay.string(from: date)
        return Holiday(
            scope: .global,
            customerId: nil,
            dateString: dateString,
            name: name,
            isHalfDay: isHalfDay,
            halfDayCutoff: isHalfDay ? TimeOfDay(hour: 13, minute: 0) : nil,
            isActive: true,
            organizationId: organizationId,
            createdByUserId: BuiltInUserId.defaultOwner,
            updatedByUserId: BuiltInUserId.defaultOwner,
            createdAt: now,
            updatedAt: now
        )
    }
}
