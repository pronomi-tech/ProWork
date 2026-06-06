//  DatabaseTestHelper.swift
//  ProWorkTests
//  Her test için temiz, dosya bazlı SQLite örneği. AppDatabase.shared
//  geçici bir dizine yönlendirilir; migration ve seed otomatik çalışır.
//  `AppDatabase` bir singleton olduğu için aynı process
//  içindeki tüm testler aynı bağlantıyı paylaşır — paralel test runner'da
//  birden çok suite eş zamanlı çalışırsa birbirlerinin DB dosyasını
//  kapatabiliyordu. `serializationLock` ile setup/teardown'ları process
//  geneli serileştiriyoruz; testler `freshDatabase()` ile çalışmaya
//  başladığında lock alınır, `teardown` lock'u serbest bırakır.

import Foundation
@testable import ProWork

enum DatabaseTestHelper {
    /// Process-wide gate. NSLock yeterli — Swift Testing/XCTest aynı süreçte
    /// çoklu suite'i thread havuzundan tetikleyebiliyor.
    private static let serializationLock = NSLock()

    /// Geçici dizinde yeni bir DB oluşturur, migration + seed'i çalıştırır.
    /// Caller sözleşmesi: dönen URL ile `teardown(at:)` çağır — aksi halde
    /// kilit serbest kalmaz ve sonraki testler asılır.
    static func freshDatabase() throws -> URL {
        serializationLock.lock()
        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("prowork-tests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let dbURL = tempDir.appendingPathComponent("test.sqlite")
            try AppDatabase.shared.configure(at: dbURL, containerDirectoryURL: tempDir)
            return dbURL
        } catch {
            // Hata fırlattıysak teardown çağrılmayabilir — kilidi burada bırak.
            serializationLock.unlock()
            throw error
        }
    }

    /// Bağlantıyı kapatır ve dosyayı siler. `freshDatabase()` çağrısı varsa
    /// process-wide kilidi de serbest bırakır.
    static func teardown(at url: URL) {
        AppDatabase.shared.close()
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parent)
        serializationLock.unlock()
    }
}
