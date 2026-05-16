//
//  ProWorkLog.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Uygulama genelinde paylaşılan os.Logger örnekleri.
//  Önceki `print(...)` çağrıları finansal bir uygulamada problemliydi:
//    - PII (kullanıcı dizini, hata mesajındaki müşteri adı vb.) düz string
//      olarak Console.app'a düşüyordu.
//    - Production'da bile output kapatılmıyordu.
//    - Audit / debug için kategori bazlı filtreleme yapılamıyordu.
//
//  `Logger` kullanarak:
//    - `privacy: .private` ile hassas alanlar maskelenir.
//    - Console.app'ta `subsystem` + `category` ile filtre yapılır.
//    - Release build'de varsayılan log seviyesi optimize edilir.
//

import Foundation
import os

// Proje SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor olduğundan enum üyelerini
// açıkça `nonisolated` işaretliyoruz. Aksi halde `Task.detached`, repository
// thread'leri ve diğer nonisolated bağlamlardan log atılamıyor (Swift 6 hatası).
// `os.Logger` Sendable olduğu için her bağlamdan güvenli.
enum ProWorkLog {
    nonisolated static let subsystem = "com.pronomi.prowork"

    nonisolated static let app = Logger(subsystem: subsystem, category: "app")
    nonisolated static let database = Logger(subsystem: subsystem, category: "database")
    nonisolated static let billing = Logger(subsystem: subsystem, category: "billing")
    nonisolated static let sync = Logger(subsystem: subsystem, category: "sync")
    nonisolated static let settings = Logger(subsystem: subsystem, category: "settings")
    nonisolated static let export = Logger(subsystem: subsystem, category: "export")
}
