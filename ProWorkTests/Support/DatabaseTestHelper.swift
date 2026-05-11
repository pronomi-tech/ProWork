//
//  DatabaseTestHelper.swift
//  ProWorkTests
//
//  Her test için temiz, dosya bazlı SQLite örneği. AppDatabase.shared
//  geçici bir dizine yönlendirilir; migration ve seed otomatik çalışır.
//

import Foundation
@testable import ProWork

enum DatabaseTestHelper {
    /// Geçici dizinde yeni bir DB oluşturur, migration + seed'i çalıştırır.
    /// Aynı `AppDatabase.shared`'i kullandığı için aynı süreçte birden fazla test paralel çalışamaz —
    /// XCTest varsayılan olarak serial çalıştırır.
    static func freshDatabase() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prowork-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbURL = tempDir.appendingPathComponent("test.sqlite")
        try AppDatabase.shared.configure(at: dbURL, containerDirectoryURL: tempDir)
        return dbURL
    }

    /// Bağlantıyı kapatır ve dosyayı siler.
    static func teardown(at url: URL) {
        AppDatabase.shared.close()
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parent)
    }
}
