//
//  Migration002BillingDocumentNumber.swift
//  ProWork
//
//  Created by Pronomi.
//
//  `billing_report_runs` tablosuna `documentNumber TEXT` kolonu ekler.
//  PDF renderer önceden run id'sinin 6 hex prefix'ini kullanıyordu — Birthday
//  paradox 5K kayıtta ~%1 çakışma demek; resmi belge numarası için kabul edilmez.
//  Çözüm: finalize anında yıl bazlı sequence sayacı tüketilip
//  "HD-2026-000123" formatında kalıcı olarak runa yazılır.
//

import Foundation

struct Migration002BillingDocumentNumber: Migration {
    let id = 2
    let name = "Add documentNumber to billing_report_runs"

    func up(_ database: AppDatabase) throws {
        try database.execute("""
        ALTER TABLE billing_report_runs
        ADD COLUMN documentNumber TEXT;
        """)

        try database.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_billing_runs_document_number
        ON billing_report_runs(organizationId, documentNumber)
        WHERE documentNumber IS NOT NULL;
        """)
    }
}
