//
//  MinimumWindowApplier.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Spec §4 — Minimum ücretlendirme penceresi.
//  Pencere işin başladığı andan itibaren hesaplanır:
//      Pencere = 60 dk, başlangıç 10:30 → pencereler 10:30–11:30, 11:30–12:30, ...
//
//  Formül:
//      ücretlendirilecek_dakika = ceil(gerçek_dakika / pencere_dakika) * pencere_dakika
//
//  Saf fonksiyon. Tüm hesap mantığı tek yerde. UI ve repository'ler bunu çağırır.
//

import Foundation

enum MinimumWindowApplier {
    /// Verilen gerçek süreyi minimum pencere kuralına göre yukarı yuvarlar.
    /// - Parameters:
    ///   - actualMinutes: Çalışmanın gerçek süresi (dakika).
    ///   - windowMinutes: Minimum pencere genişliği (dakika). 0 veya negatif ise yuvarlama yapılmaz.
    /// - Returns: Ücretlendirilecek süre (dakika).
    static func apply(actualMinutes: Int, windowMinutes: Int?) -> Int {
        guard let window = windowMinutes, window > 0 else {
            return max(0, actualMinutes)
        }
        if actualMinutes <= 0 { return 0 }
        let nWindows = (actualMinutes + window - 1) / window  // ceiling division
        return nWindows * window
    }

    /// Saniye cinsinden gerçek süre alıp dakika olarak ücretlendirilecek süreyi döner.
    static func applySeconds(actualSeconds: Int, windowMinutes: Int?) -> Int {
        guard actualSeconds > 0 else { return 0 }
        // Saniyeyi dakikaya çevirirken yukarı yuvarla (1 saniye bile 1 dakika sayılır)
        let actualMinutes = (actualSeconds + 59) / 60
        return apply(actualMinutes: actualMinutes, windowMinutes: windowMinutes)
    }
}
