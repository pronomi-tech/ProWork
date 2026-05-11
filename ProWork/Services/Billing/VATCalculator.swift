//
//  VATCalculator.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Adlandırılmış KDV tanımlarına (VatRate) göre satır KDV'sini hesaplar.
//
//  Çözüm sırası (en spesifik kazanır):
//    1. project.vatRateId       — projeye atanmış tanım
//    2. customer.vatRateId      — müşteriye atanmış tanım
//    3. category.vatRateId      — kategoriye atanmış tanım
//    4. default                 — `isDefault = true` tanım (yoksa 0)
//
//  `isExempt = true` tanım uygulandığında oran 0 kabul edilir; çağıran
//  taraf snapshot için `appliedExempt`'i kullanır (PDF/raporda "Muaf").
//

import Foundation

enum VatRateOrigin: String, Hashable {
    case project
    case customer
    case category
    case `default`
    case none
}

struct VATCalculationResult: Hashable {
    /// Uygulanan oran (0.20 vb.); muafiyet ise 0.
    let rate: Decimal
    /// KDV tutarı (minor unit).
    let vatMinor: Int
    /// Toplam (subtotal + vat) (minor unit).
    let totalMinor: Int
    /// Muafiyet tanımı uygulandı mı.
    let isExempt: Bool
    /// Hangi seviyeden geldiği (debug/audit).
    let origin: VatRateOrigin
}

final class VATCalculator {
    private let ratesById: [String: VatRate]
    private let defaultRate: VatRate?

    /// Caller, organizasyona ait tüm aktif KDV tanımlarını yüklemiş olmalı.
    init(rates: [VatRate]) {
        let active = rates.filter { $0.isActive && $0.deletedAt == nil }
        self.ratesById = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        self.defaultRate = active.first(where: { $0.isDefault })
    }

    /// Verilen müşteri/proje/kategori için uygulanacak KDV oranını ve sonucunu döner.
    /// `dateString` parametresi imza uyumu için tutulur; tarihli oranlar artık desteklenmez.
    func calculate(
        subtotalMinor: Int,
        customerVatRateId: String?,
        projectVatRateId: String?,
        categoryVatRateId: String?,
        dateString: String = ""
    ) -> VATCalculationResult {
        let resolved = resolve(
            customerVatRateId: customerVatRateId,
            projectVatRateId: projectVatRateId,
            categoryVatRateId: categoryVatRateId
        )

        guard let rate = resolved.rate else {
            return VATCalculationResult(
                rate: 0,
                vatMinor: 0,
                totalMinor: subtotalMinor,
                isExempt: false,
                origin: .none
            )
        }

        let vatMinor = rate.vatMinor(forSubtotal: subtotalMinor)
        return VATCalculationResult(
            rate: rate.isExempt ? 0 : rate.rate,
            vatMinor: vatMinor,
            totalMinor: subtotalMinor + vatMinor,
            isExempt: rate.isExempt,
            origin: resolved.origin
        )
    }

    private struct Resolved {
        let rate: VatRate?
        let origin: VatRateOrigin
    }

    private func resolve(
        customerVatRateId: String?,
        projectVatRateId: String?,
        categoryVatRateId: String?
    ) -> Resolved {
        if let id = projectVatRateId, let rate = ratesById[id] {
            return Resolved(rate: rate, origin: .project)
        }
        if let id = customerVatRateId, let rate = ratesById[id] {
            return Resolved(rate: rate, origin: .customer)
        }
        if let id = categoryVatRateId, let rate = ratesById[id] {
            return Resolved(rate: rate, origin: .category)
        }
        if let rate = defaultRate {
            return Resolved(rate: rate, origin: .default)
        }
        return Resolved(rate: nil, origin: .none)
    }
}
