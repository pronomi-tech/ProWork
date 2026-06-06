//  DatabaseSessionController.swift
//  ProWork
//  Created by Pronomi.

import AppKit
import Combine
import Foundation
import os
import SwiftUI

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

    /// Non-nil when the journal mode fell back to MEMORY (sidecar files
    /// couldn't be created — typically in a cloud-sync folder like
    /// OneDrive/iCloud). No crash-safety in that mode; the UI shows a
    /// persistent warning + "Move data file" button. When `nil`, the
    /// mode is durable (WAL/TRUNCATE) and no warning is shown.
    @Published private(set) var durabilityWarning: String?

    /// Populated during the open flow when the selected folder contains
    /// more than one `.sqlite` file; the UI uses this to ask which one
    /// the user wants to open. When non-nil, the UI shows a selection sheet.
    @Published var pendingDatabaseSelection: PendingDatabaseSelection?

    struct PendingDatabaseSelection: Identifiable {
        let id = UUID()
        let folder: URL
        let files: [URL]
    }

    /// Folder security-scoped URL that must stay open until
    /// `pendingDatabaseSelection` resolves (the sheet is async, so it
    /// can't be closed via defer; it's closed manually on confirm/cancel).
    private var pendingSelectionScopedFolder: URL?

    private let locationStore = DatabaseLocationStore()
    private var hasBootstrapped = false
    /// For URLs resolved from a security-scoped bookmark under sandboxing,
    /// `startAccessingSecurityScopedResource()` is mandatory — otherwise
    /// SQLite cannot write to the file. We keep this list so every
    /// `start` call can be paired with a matching `stop`.
    private var activeScopedResources: [URL] = []

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

    /// Returns true once an active database has been opened in this app
    /// session. While `false`, `AppServices` has never executed a query and
    /// it is safe to swap the database without relaunching. Once `true`,
    /// any further database change MUST relaunch because services and view
    /// models hold cached state (settings store, automation controller,
    /// currency converter, etc.) that was populated from the previous DB
    private var hasActiveDatabase: Bool {
        if case .ready = phase { return true }
        return activeDatabaseURL != nil
    }

    // MARK: - Create (name first, then folder)

    /// New DB creation: first ask for a name, then pick a folder →
    /// `<folder>/<name>.sqlite`. Picking a FOLDER grants directory-level
    /// access (sidecar files can be created → WAL durable); the custom
    /// name allows multiple data files in the same folder.
    func promptToCreateDatabase() {
        guard let rawName = requestDatabaseName() else { return }
        let fileName = sanitizedDatabaseFileName(from: rawName)

        guard let folder = chooseDatabaseFolder(
            prompt: hasActiveDatabase
                ? localized("database.panel.create.prompt.restart", defaultValue: "Oluştur ve Yeniden Başlat")
                : localized("database.panel.create.prompt", defaultValue: "Oluştur"),
            message: String(
                format: localized("database.panel.createFolder.message", defaultValue: "'%@' bu klasörde oluşturulacak. (Crash-safe WAL modu için klasör erişimi gerekir.)"),
                fileName
            )
        ) else { return }

        let dbURL = folder.appendingPathComponent(fileName, isDirectory: false)
        let startedScope = folder.startAccessingSecurityScopedResource()
        defer { if startedScope { folder.stopAccessingSecurityScopedResource() } }

        let location = ResolvedDatabaseLocation(databaseURL: dbURL, containerDirectoryURL: folder)
        if hasActiveDatabase {
            persistSelectionAndRelaunch(location)
        } else {
            do {
                try openDatabase(using: location, persistSelection: true)
            } catch {
                phase = .needsSelection(message: "\(localized("database.error.createFailed", defaultValue: "Yeni veri dosyası oluşturulamadı.")) \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Open (folder first, then file list)

    /// Existing DB open: first pick a folder (directory scope → WAL),
    /// then list the `.sqlite`/`.db`/`.sqlite3` files inside it. If
    /// there's a single file, open it directly; otherwise the user
    /// picks from a selection sheet.
    func promptToOpenExistingDatabase() {
        guard let folder = chooseDatabaseFolder(
            prompt: hasActiveDatabase
                ? localized("database.panel.open.prompt.restart", defaultValue: "Seç ve Yeniden Başlat")
                : localized("database.panel.open.prompt", defaultValue: "Aç"),
            message: localized("database.panel.openFolder.message", defaultValue: "Veri dosyalarının bulunduğu klasörü seçin; içindeki dosyalardan birini açabilirsiniz.")
        ) else { return }

        // Start the folder scope and keep it OPEN until the selection
        // resolves (the sheet is async). Listing happens under this scope.
        let started = folder.startAccessingSecurityScopedResource()
        let files = databaseFiles(in: folder)

        guard !files.isEmpty else {
            if started { folder.stopAccessingSecurityScopedResource() }
            let message = localized("database.error.noDatabaseInFolder", defaultValue: "Seçilen klasörde bir veri dosyası (.sqlite) bulunamadı.")
            if hasActiveDatabase {
                settingsMessage = message
            } else {
                phase = .needsSelection(message: message)
            }
            return
        }

        if files.count == 1 {
            // Single file: open directly, don't release the scope until
            // the open is finished.
            defer { if started { folder.stopAccessingSecurityScopedResource() } }
            openSelectedDatabase(files[0], in: folder)
        } else {
            // Multiple files: pick via the sheet. The scope stays open;
            // it's closed on confirm/cancel.
            pendingSelectionScopedFolder = started ? folder : nil
            pendingDatabaseSelection = PendingDatabaseSelection(folder: folder, files: files)
        }
    }

    /// Called when a file is confirmed from the selection sheet.
    func confirmDatabaseSelection(_ fileURL: URL) {
        let folder = pendingDatabaseSelection?.folder ?? fileURL.deletingLastPathComponent()
        defer {
            if let scoped = pendingSelectionScopedFolder {
                scoped.stopAccessingSecurityScopedResource()
                pendingSelectionScopedFolder = nil
            }
            pendingDatabaseSelection = nil
        }
        openSelectedDatabase(fileURL, in: folder)
    }

    /// Called when the selection sheet is cancelled.
    func cancelDatabaseSelection() {
        if let scoped = pendingSelectionScopedFolder {
            scoped.stopAccessingSecurityScopedResource()
            pendingSelectionScopedFolder = nil
        }
        pendingDatabaseSelection = nil
    }

    private func openSelectedDatabase(_ dbURL: URL, in folder: URL) {
        let location = ResolvedDatabaseLocation(databaseURL: dbURL, containerDirectoryURL: folder)
        if hasActiveDatabase {
            persistSelectionAndRelaunch(location)
        } else {
            do {
                try openDatabase(using: location, persistSelection: true)
            } catch {
                phase = .needsSelection(message: "\(localized("database.error.openFailed", defaultValue: "Seçilen veri dosyası açılamadı.")) \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Folder / name helpers

    /// Shared NSOpenPanel for folder selection.
    private func chooseDatabaseFolder(prompt: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = localized("database.panel.folder.title", defaultValue: "ProWork Veri Klasörü")
        panel.prompt = prompt
        panel.message = message
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Simple text-input dialog for the new file name (NSAlert + text field).
    private func requestDatabaseName() -> String? {
        let alert = NSAlert()
        alert.messageText = localized("database.name.title", defaultValue: "Veri Dosyası Adı")
        alert.informativeText = localized("database.name.message", defaultValue: "Oluşturulacak veri dosyasının adını girin (örn. müşteri/proje adı).")
        alert.addButton(withTitle: localized("common.continue", defaultValue: "Devam"))
        alert.addButton(withTitle: localized("common.cancel", defaultValue: "Vazgeç"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "ProWork"
        field.stringValue = "ProWork"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    /// Converts the user-supplied name into a valid `.sqlite` filename.
    private func sanitizedDatabaseFileName(from name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines)
        var base = name.components(separatedBy: invalid).joined()
            .trimmingCharacters(in: .whitespaces)
        if base.isEmpty { base = "ProWork" }
        if base.lowercased().hasSuffix(".sqlite") { return base }
        return base + ".sqlite"
    }

    /// Returns every DB file in the folder (alphabetical).
    private func databaseFiles(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []
        let databaseExtensions: Set<String> = ["sqlite", "db", "sqlite3"]
        return contents
            .filter { databaseExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Triggered by the "Move Data File" button in the durability warning.
    /// **Copies** the current .sqlite to the local destination chosen by
    /// the user (does not create an empty DB — the data is preserved),
    /// saves the new location and relaunches.
    /// The warning only appears in MEMORY journal mode; in that mode
    /// `-wal`/`-journal` sidecar files don't exist anyway, so copying
    /// just the main file moves every committed row.
    func relocateDatabase() {
        guard let currentURL = activeDatabaseURL else {
            // If there's no active DB, fall through to the standard create flow.
            promptToCreateDatabase()
            return
        }

        // FOLDER selection: grants directory-level access to the new
        // folder → sidecar files can be created → WAL durable. The file
        // is copied to the destination folder keeping its current name
        // (multi-file support).
        guard let folder = chooseDatabaseFolder(
            prompt: localized("database.panel.relocate.prompt", defaultValue: "Taşı ve Yeniden Başlat"),
            message: localized("database.panel.relocateFolder.message", defaultValue: "Veri dosyasının kopyalanacağı yerel (bulut-senkronsuz) klasörü seçin.")
        ) else { return }
        let destination = folder.appendingPathComponent(currentURL.lastPathComponent, isDirectory: false)

        // Start the folder scope — needed to create the bookmark and
        // write the file; released at the end of the function (the
        // relaunch is going to terminate the process anyway).
        let startedScope = folder.startAccessingSecurityScopedResource()
        defer { if startedScope { folder.stopAccessingSecurityScopedResource() } }

        // Trying to copy a file onto itself (user picks the existing
        // folder) would delete the source and lose data; in that case
        // skip the copy and just refresh the folder bookmark + relaunch
        // to try moving to WAL.
        let isSameLocation = destination.standardizedFileURL == currentURL.standardizedFileURL

        do {
            // Close the open connection so the file copy is consistent;
            // relaunch will reopen cleanly in the new process.
            AppDatabase.shared.close()
            if !isSameLocation {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: currentURL, to: destination)
            }
            _ = try locationStore.saveActiveDatabase(url: destination)
            // Ensure the bookmark hits disk — if relaunch's terminate
            // runs before the UserDefaults flush, the new process would
            // read the old bookmark.
            UserDefaults.standard.synchronize()
            // Move succeeded: the persistent banner should now show the
            // "restart needed" message rather than the old "MEMORY risk"
            // message. If the relaunch works (release build) the new
            // process opens directly; if not (debug sandbox `open -n`
            // restriction) the next manual close+open lands on the new
            // (local, WAL durable) location and the warning disappears.
            durabilityWarning = localized(
                "database.relocate.restartNeeded",
                defaultValue: "Veri dosyası taşındı. Değişikliğin tam olarak geçerli olması için uygulamayı kapatıp yeniden açın."
            )
            settingsMessage = localized("database.message.relocatedRelaunching", defaultValue: "Veri dosyası taşındı. Uygulama yeniden başlatılıyor.")
            AppRelauncher.relaunch()
        } catch {
            settingsMessage = "\(localized("database.error.relocateFailed", defaultValue: "Veri dosyası taşınamadı:")) \(error.localizedDescription)"
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
        // URLs resolved from a bookmark require security-scoped access;
        // without calling `startAccessing...` before opening the SQLite
        // file, reads/writes fail under the sandbox.
        beginAccessingScopedResources(for: location)

        try AppDatabase.shared.configure(
            at: location.databaseURL,
            containerDirectoryURL: location.containerDirectoryURL
        )

        // Migration001 hardcoded religious holidays for 2024-2030.
        // Run the generator to fill in 2031+ so there's no gap. It
        // doesn't touch existing rows, so it's safe to call on every launch.
        // a silent failure here meant Islamic holiday
        // calendar data could be missing while billing assumed the full
        // range was populated (overtime/holiday line rates would then be
        // computed against a non-holiday classification). Still don't
        // abort session bootstrap on this — but surface as a toast so the
        // user notices and an admin can investigate.
        do {
            try IslamicHolidayBootstrap().ensurePopulated(
                currentYear: AppCalendar.istanbul.component(.year, from: Date())
            )
        } catch {
            ProWorkLog.app.error("Islamic holiday bootstrap failed: \(error.localizedDescription, privacy: .public)")
            let message = ProWorkLocalizer.shared.string(
                "app.error.holidayBootstrap",
                defaultValue: "Dini bayram takvimi yüklenemedi; tatil hesapları eksik olabilir."
            )
            Task { @MainActor in
                ProWorkToastStore.shared.show(message, style: .warning)
            }
        }

        let resolvedLocation: ResolvedDatabaseLocation
        if persistSelection {
            resolvedLocation = try locationStore.saveActiveDatabase(url: location.databaseURL)
        } else {
            resolvedLocation = location
        }

        activeDatabaseURL = resolvedLocation.databaseURL
        settingsMessage = nil
        phase = .ready(url: resolvedLocation.databaseURL)

        // Durability warning: if sidecar files couldn't be created and
        // we fell back to MEMORY, surface a visible warning to the user.
        // WAL/TRUNCATE are durable; no warning needed.
        if AppDatabase.shared.resolvedJournalMode.isDurable {
            durabilityWarning = nil
        } else {
            durabilityWarning = localized(
                "database.durabilityWarning.message",
                defaultValue: "Veritabanı yan dosya yazamadığı için güvensiz (MEMORY) modda çalışıyor — büyük olasılıkla OneDrive/iCloud gibi bir bulut klasöründe. Uygulama çökerse veya güç giderse veri kaybı/bozulma riski var. Veri dosyasını yerel (bulut-senkronsuz) bir klasöre taşıyın."
            )
        }
    }

    /// Opens both `databaseURL` and the optional container URL as
    /// security-scoped; every successful open is tracked for teardown.
    /// If `start` returns `false` access may still be granted (URL is
    /// outside the scope); in that case `stop` must NOT be called.
    private func beginAccessingScopedResources(
        for location: ResolvedDatabaseLocation
    ) {
        endAccessingScopedResources()

        if location.databaseURL.startAccessingSecurityScopedResource() {
            activeScopedResources.append(location.databaseURL)
        }
        if let containerURL = location.containerDirectoryURL,
           containerURL.startAccessingSecurityScopedResource() {
            activeScopedResources.append(containerURL)
        }
    }

    private func endAccessingScopedResources() {
        for url in activeScopedResources {
            url.stopAccessingSecurityScopedResource()
        }
        activeScopedResources.removeAll()
    }

    /// Deinit is nonisolated, but `activeScopedResources` is a
    /// `@MainActor`-isolated stored property. Reading it directly here
    /// already triggers a Swift 6 warning and will be a hard error
    /// once `default-isolation MainActor` enforcement tightens. The
    /// store is only ever mutated on the main actor; at deinit no
    /// other actor can still hold a reference (the object is being
    /// torn down). Snapshotting via `Mirror` skips the isolation check
    /// while preserving the cleanup; we still bail on an unexpected
    /// shape rather than swallow it silently.
    deinit {
        let mirror = Mirror(reflecting: self)
        let snapshot = mirror.children
            .first(where: { $0.label == "activeScopedResources" })?
            .value as? [URL]
        guard let snapshot else { return }
        for url in snapshot {
            url.stopAccessingSecurityScopedResource()
        }
    }

    private func persistSelectionAndRelaunch(_ location: ResolvedDatabaseLocation) {
        do {
            try createDatabaseIfNeeded(at: location)
            _ = try locationStore.saveActiveDatabase(url: location.databaseURL)
            settingsMessage = localized("database.message.changedRelaunching", defaultValue: "Veri dosyası değişti. Uygulama yeniden başlatılıyor.")
            // Ensure the bookmark hits disk (if relaunch's terminate runs
            // before the flush, the new process would read the old bookmark).
            UserDefaults.standard.synchronize()
            AppRelauncher.relaunch()
        } catch {
            settingsMessage = "\(localized("database.error.saveFailed", defaultValue: "Veri dosyası kaydedilemedi:")) \(error.localizedDescription)"
        }
    }

    private func createDatabaseIfNeeded(at location: ResolvedDatabaseLocation) throws {
        guard !FileManager.default.fileExists(atPath: location.databaseURL.path) else {
            return
        }

        try AppDatabase.shared.configure(
            at: location.databaseURL,
            containerDirectoryURL: location.containerDirectoryURL
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
    /// Terminates the running app and starts a new instance via
    /// `/usr/bin/open -n bundle.path`. The previous code used
    /// `Task.detached { sleep; run() }` and called `terminate`
    /// immediately; `terminate` could kill the detached task, so the
    /// relaunch could be silently lost. Now we run `open` synchronously
    /// and wait for it to complete before terminating. `open` actually
    /// hands the new instance to LaunchServices and exits quickly;
    /// `waitUntilExit` typically blocks for under 100 ms.
    /// terminate is now gated on the launcher actually starting.
    /// Previously every failure path (sandbox refusal, missing `open`,
    /// permission denial) still ran `NSApp.terminate(nil)`, killing the
    /// current process with no replacement — silent data loss because
    /// the user expected a fresh window. On failure we keep the
    /// process alive, surface a toast, and let the user retry. The
    /// `open -n` handoff itself returns quickly (~100 ms) so the
    /// blocking wait stays bounded.
    static func relaunch() {
        let bundleURL = Bundle.main.bundleURL

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundleURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            ProWorkLog.app.error("App relaunch failed: \(error.localizedDescription, privacy: .public)")
            ProWorkToastStore.shared.show(
                ProWorkLocalizer.shared.string(
                    "app.error.relaunchFailed",
                    defaultValue: "Uygulama yeniden başlatılamadı. Lütfen kendiniz kapatıp açın."
                ),
                style: .error
            )
            return
        }

        // Only terminate the current process once the launcher has
        // genuinely accepted the handoff; if `process.terminationStatus`
        // is non-zero `open` couldn't reach LaunchServices and the
        // replacement never started.
        guard process.terminationStatus == 0 else {
            ProWorkLog.app.error("App relaunch open exited \(process.terminationStatus, privacy: .public); keeping current process alive.")
            ProWorkToastStore.shared.show(
                ProWorkLocalizer.shared.string(
                    "app.error.relaunchFailed",
                    defaultValue: "Uygulama yeniden başlatılamadı. Lütfen kendiniz kapatıp açın."
                ),
                style: .error
            )
            return
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

                    Text(settingsStore.localized("database.setup.subtitle", defaultValue: "ProWork verilerini seçtiğiniz bir klasörde 'ProWork.sqlite' olarak saklar. Crash-safe WAL modu için dosya değil klasör seçilir."))
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
                        title: settingsStore.localized("database.setup.open.title", defaultValue: "Mevcut Veriyi Aç"),
                        subtitle: settingsStore.localized("database.setup.open.subtitle", defaultValue: "İçinde 'ProWork.sqlite' bulunan klasörü seçin."),
                        buttonTitle: settingsStore.localized("database.setup.open.button", defaultValue: "Klasör Seç"),
                        systemImage: "folder"
                    ) {
                        sessionController.promptToOpenExistingDatabase()
                    }

                    actionCard(
                        title: settingsStore.localized("database.setup.create.title", defaultValue: "Yeni Veri Oluştur"),
                        subtitle: settingsStore.localized("database.setup.create.subtitle", defaultValue: "Verinin saklanacağı klasörü seçin. 'ProWork.sqlite' ve gerekli tablolar otomatik hazırlanır."),
                        buttonTitle: settingsStore.localized("database.setup.create.button", defaultValue: "Klasör Seç ve Oluştur"),
                        systemImage: "plus"
                    ) {
                        sessionController.promptToCreateDatabase()
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
