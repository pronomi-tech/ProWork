//
//  DatabaseSessionController.swift
//  ProWork
//
//  Created by Pronomi.
//

import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DatabaseSessionController: ObservableObject {
    struct ResolvedDatabaseLocation {
        let databaseURL: URL
        let containerDirectoryURL: URL?
    }

    enum Phase: Equatable {
        case launching
        case needsSelection(message: String?)
        case ready(url: URL)
    }

    @Published private(set) var phase: Phase = .launching
    @Published private(set) var activeDatabaseURL: URL?
    @Published var settingsMessage: String?

    private let locationStore = DatabaseLocationStore()
    private var hasBootstrapped = false

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    func bootstrapIfNeeded() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        do {
            guard let location = try locationStore.resolveActiveDatabaseLocation() else {
                phase = .needsSelection(message: nil)
                return
            }

            try openDatabase(using: location, persistSelection: false)
        } catch {
            locationStore.clearActiveDatabase()
            phase = .needsSelection(
                message: "\(localized("database.error.lastOpenFailed", defaultValue: "Son kullanılan veri dosyası açılamadı. Yeni bir dosya seçin veya oluşturun.")) \(error.localizedDescription)"
            )
        }
    }

    func promptToOpenExistingDatabase(restartAfterSelection: Bool) {
        let panel = NSOpenPanel()
        panel.title = localized("database.panel.open.title", defaultValue: "ProWork Veri Dosyasını Seçin")
        panel.prompt = restartAfterSelection
            ? localized("database.panel.open.prompt.restart", defaultValue: "Seç ve Yeniden Başlat")
            : localized("database.panel.open.prompt", defaultValue: "Aç")
        panel.message = localized("database.panel.open.message", defaultValue: "Mevcut bir ProWork SQLite veri dosyası seçin.")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = sqliteContentTypes

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if restartAfterSelection {
            persistSelectionAndRelaunch(url)
        } else {
            do {
                try openDatabase(at: url, persistSelection: true)
            } catch {
                phase = .needsSelection(message: "\(localized("database.error.openFailed", defaultValue: "Seçilen veri dosyası açılamadı.")) \(error.localizedDescription)")
            }
        }
    }

    func promptToCreateDatabase(restartAfterSelection: Bool) {
        let panel = NSSavePanel()
        panel.title = localized("database.panel.create.title", defaultValue: "Yeni ProWork Veri Dosyası Oluştur")
        panel.prompt = restartAfterSelection
            ? localized("database.panel.create.prompt.restart", defaultValue: "Oluştur ve Yeniden Başlat")
            : localized("database.panel.create.prompt", defaultValue: "Oluştur")
        panel.message = localized("database.panel.create.message", defaultValue: "Yeni veritabanı dosyasının kaydedileceği konumu seçin.")
        panel.nameFieldStringValue = defaultDatabaseFilename
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [sqlitePrimaryContentType]
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        let url = normalizedDatabaseCreationURL(from: selectedURL)

        if restartAfterSelection {
            persistSelectionAndRelaunch(url)
        } else {
            do {
                try openDatabase(at: url, persistSelection: true)
            } catch {
                phase = .needsSelection(message: "\(localized("database.error.createFailed", defaultValue: "Yeni veri dosyası oluşturulamadı.")) \(error.localizedDescription)")
            }
        }
    }

    func revealActiveDatabaseInFinder() {
        guard let activeDatabaseURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([activeDatabaseURL])
    }

    private func openDatabase(at url: URL, persistSelection: Bool) throws {
        let location = ResolvedDatabaseLocation(
            databaseURL: url,
            containerDirectoryURL: url.deletingLastPathComponent()
        )

        try openDatabase(using: location, persistSelection: persistSelection)
    }

    private func openDatabase(using location: ResolvedDatabaseLocation, persistSelection: Bool) throws {
        try AppDatabase.shared.configure(
            at: location.databaseURL,
            containerDirectoryURL: location.containerDirectoryURL
        )

        let resolvedLocation: ResolvedDatabaseLocation
        if persistSelection {
            resolvedLocation = try locationStore.saveActiveDatabase(url: location.databaseURL)
        } else {
            resolvedLocation = location
        }

        activeDatabaseURL = resolvedLocation.databaseURL
        settingsMessage = nil
        phase = .ready(url: resolvedLocation.databaseURL)
    }

    private func persistSelectionAndRelaunch(_ url: URL) {
        do {
            try createDatabaseIfNeeded(at: url)
            _ = try locationStore.saveActiveDatabase(url: url)
            settingsMessage = localized("database.message.changedRelaunching", defaultValue: "Veri dosyası değişti. Uygulama yeniden başlatılıyor.")
            AppRelauncher.relaunch()
        } catch {
            settingsMessage = "\(localized("database.error.saveFailed", defaultValue: "Veri dosyası kaydedilemedi:")) \(error.localizedDescription)"
        }
    }

    private var sqliteContentTypes: [UTType] {
        let types = [
            sqlitePrimaryContentType,
            UTType(filenameExtension: "db"),
            UTType(filenameExtension: "sqlite3")
        ].compactMap { $0 }

        return types.isEmpty ? [.data] : types
    }

    private var sqlitePrimaryContentType: UTType {
        UTType(filenameExtension: "sqlite") ?? .data
    }

    private var defaultDatabaseFilename: String {
        "ProWork"
    }

    private func normalizedDatabaseCreationURL(from url: URL) -> URL {
        let duplicateSuffix = ".sqlite.sqlite"
        let filename = url.lastPathComponent

        guard filename.lowercased().hasSuffix(duplicateSuffix) else {
            return url
        }

        let normalizedFilename = String(filename.dropLast(".sqlite".count))
        return url.deletingLastPathComponent().appendingPathComponent(normalizedFilename, isDirectory: false)
    }

    private func createDatabaseIfNeeded(at url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try AppDatabase.shared.configure(
            at: url,
            containerDirectoryURL: url.deletingLastPathComponent()
        )
        AppDatabase.shared.close()
    }
}

private final class DatabaseLocationStore {
    private enum Keys {
        static let activeDatabaseBookmark = "activeDatabaseBookmark"
        static let activeDatabaseContainerBookmark = "activeDatabaseContainerBookmark"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func saveActiveDatabase(url: URL) throws -> DatabaseSessionController.ResolvedDatabaseLocation {
        let databaseBookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(databaseBookmark, forKey: Keys.activeDatabaseBookmark)

        let containerURL = url.deletingLastPathComponent()
        if let containerBookmark = try? containerURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(containerBookmark, forKey: Keys.activeDatabaseContainerBookmark)
        } else {
            defaults.removeObject(forKey: Keys.activeDatabaseContainerBookmark)
        }

        return try resolveActiveDatabaseLocation()
            ?? DatabaseSessionController.ResolvedDatabaseLocation(
                databaseURL: url,
                containerDirectoryURL: containerURL
            )
    }

    func resolveActiveDatabaseLocation() throws -> DatabaseSessionController.ResolvedDatabaseLocation? {
        guard let databaseBookmark = defaults.data(forKey: Keys.activeDatabaseBookmark) else {
            return nil
        }

        var isDatabaseBookmarkStale = false
        let databaseURL = try URL(
            resolvingBookmarkData: databaseBookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isDatabaseBookmarkStale
        )

        let containerDirectoryURL: URL?
        if let containerBookmark = defaults.data(forKey: Keys.activeDatabaseContainerBookmark) {
            var isContainerBookmarkStale = false
            containerDirectoryURL = try URL(
                resolvingBookmarkData: containerBookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isContainerBookmarkStale
            )

            if isContainerBookmarkStale {
                _ = try saveActiveDatabase(url: databaseURL)
            }
        } else {
            containerDirectoryURL = nil
        }

        if isDatabaseBookmarkStale {
            _ = try saveActiveDatabase(url: databaseURL)
        }

        return DatabaseSessionController.ResolvedDatabaseLocation(
            databaseURL: databaseURL,
            containerDirectoryURL: containerDirectoryURL
        )
    }

    func clearActiveDatabase() {
        defaults.removeObject(forKey: Keys.activeDatabaseBookmark)
        defaults.removeObject(forKey: Keys.activeDatabaseContainerBookmark)
    }
}

private enum AppRelauncher {
    static func relaunch() {
        let bundlePath = Bundle.main.bundlePath.replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 0.5; open -n \"\(bundlePath)\""
        ]

        do {
            try process.run()
        } catch {
            print("App relaunch failed:", error.localizedDescription)
        }

        NSApp.terminate(nil)
    }
}

struct DatabaseSetupView: View {
    @EnvironmentObject private var sessionController: DatabaseSessionController
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let message: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    Text(settingsStore.localized("database.setup.title", defaultValue: "Veri Dosyası Seçin"))
                        .proWorkTextStyle(.title2)
                        .bold()

                    Text(settingsStore.localized("database.setup.subtitle", defaultValue: "ProWork verilerini otomatik oluşturulan konum yerine sizin seçtiğiniz SQLite dosyasında tutar."))
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                if let message {
                    Text(message)
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.red)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: 560)
                }

                VStack(alignment: .leading, spacing: 16) {
                    actionCard(
                        title: settingsStore.localized("database.setup.open.title", defaultValue: "Mevcut Veri Dosyasını Aç"),
                        subtitle: settingsStore.localized("database.setup.open.subtitle", defaultValue: "Daha önce oluşturduğunuz `.sqlite`, `.db` veya `.sqlite3` dosyasını seçin."),
                        buttonTitle: settingsStore.localized("database.setup.open.button", defaultValue: "Dosya Seç"),
                        systemImage: "folder"
                    ) {
                        sessionController.promptToOpenExistingDatabase(restartAfterSelection: false)
                    }

                    actionCard(
                        title: settingsStore.localized("database.setup.create.title", defaultValue: "Yeni Veri Dosyası Oluştur"),
                        subtitle: settingsStore.localized("database.setup.create.subtitle", defaultValue: "Kaydetmek istediğiniz klasörü ve dosya adını seçin. Gerekli tablo ve varsayılan kayıtlar otomatik hazırlanır."),
                        buttonTitle: settingsStore.localized("database.setup.create.button", defaultValue: "Yeni Oluştur"),
                        systemImage: "plus"
                    ) {
                        sessionController.promptToCreateDatabase(restartAfterSelection: false)
                    }
                }
                .frame(maxWidth: 680)
            }
            .padding(32)
        }
    }

    private func actionCard(
        title: String,
        subtitle: String,
        buttonTitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .proWorkTextStyle(.headline)

                Text(subtitle)
                    .proWorkTextStyle(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    action()
                } label: {
                    ProWorkButtonLabel(title: buttonTitle, systemImage: systemImage)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}
