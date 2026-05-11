//
//  CompanyProfileView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CompanyProfileView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var profile: CompanyProfile = CompanyProfile(legalName: "")
    @State private var errorMessage: String?
    @State private var savedNotice: String?
    @State private var isImporterPresented = false

    private let repository = CompanyProfileRepository()

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("companyProfile.title", defaultValue: "Şirket Profili"),
            subtitle: settingsStore.localized("companyProfile.subtitle", defaultValue: "Hizmet dökümlerinde ve PDF çıktılarında görünecek şirket kimliğinizi tanımlayın."),
            errorMessage: errorMessage,
            savedNotice: savedNotice,
            toolbar: {
                Button {
                    save()
                } label: {
                    ProWorkButtonLabel(title: settingsStore.localized("common.save", defaultValue: "Kaydet"), systemImage: "checkmark", minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        ) {
            logoSection

            SettingsCard {
                Text(settingsStore.localized("companyProfile.section.identity", defaultValue: "Kimlik"))
                    .proWorkTextStyle(.headline)
                identityFields
            }

            SettingsCard {
                Text(settingsStore.localized("companyProfile.section.contact", defaultValue: "İletişim"))
                    .proWorkTextStyle(.headline)
                contactFields
            }

            SettingsCard {
                Text(settingsStore.localized("companyProfile.section.payment", defaultValue: "Ödeme"))
                    .proWorkTextStyle(.headline)
                paymentFields
            }
        }
        .onAppear { load() }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.png, .jpeg, .image],
            allowsMultipleSelection: false
        ) { result in
            handleLogoImport(result: result)
        }
    }

    // MARK: - Logo

    private var logoSection: some View {
        SettingsCard {
            Text(settingsStore.localized("companyProfile.logo.title", defaultValue: "Logo"))
                .proWorkTextStyle(.headline)

            HStack(alignment: .top, spacing: 16) {
                logoPreview
                    .frame(width: 220, height: 88)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.quaternary, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        ProWorkButtonLabel(title: settingsStore.localized("companyProfile.logo.select", defaultValue: "Logo Seç"), systemImage: "photo")
                    }
                    .buttonStyle(.bordered)

                    if profile.logoData != nil {
                        Button(role: .destructive) {
                            profile.logoData = nil
                        } label: {
                            ProWorkButtonLabel(title: settingsStore.localized("companyProfile.logo.remove", defaultValue: "Kaldır"), systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var logoPreview: some View {
        if let data = profile.logoData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .padding(8)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "building.2")
                    .proWorkFont(size: 28)
                    .foregroundStyle(.tertiary)
                Text(settingsStore.localized("companyProfile.logo.empty", defaultValue: "Logo yok"))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Field groups

    private var identityFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(label: settingsStore.localized("companyProfile.field.legalName", defaultValue: "Ünvan"), required: true) {
                ProWorkTextField(placeholder: settingsStore.localized("companyProfile.field.legalName.placeholder", defaultValue: "Şirket Ünvanı"), text: $profile.legalName)
                    .frame(maxWidth: 480)
            }
            field(label: settingsStore.localized("companyProfile.field.tradeName", defaultValue: "Ticari Ad")) {
                ProWorkTextField(placeholder: settingsStore.localized("companyProfile.field.tradeName.placeholder", defaultValue: "Marka adı"), text: bindOptional(\.tradeName))
                    .frame(maxWidth: 480)
            }
            HStack(alignment: .top, spacing: 16) {
                field(label: settingsStore.localized("companyProfile.field.taxNumber", defaultValue: "Vergi No")) {
                    ProWorkNumberField(
                        placeholder: "00000000000",
                        text: taxNumberBinding,
                        style: .integer(maxDigits: 11)
                    )
                        .frame(maxWidth: 220)
                }
                field(label: settingsStore.localized("companyProfile.field.taxOffice", defaultValue: "Vergi Dairesi")) {
                    ProWorkTextField(placeholder: settingsStore.localized("companyProfile.field.taxOffice.placeholder", defaultValue: "Daire"), text: bindOptional(\.taxOffice))
                        .frame(maxWidth: 240)
                }
                Spacer()
            }
        }
    }

    private var contactFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(label: settingsStore.localized("companyProfile.field.address", defaultValue: "Adres")) {
                ProWorkTextEditor(text: bindOptional(\.address), minHeight: 70)
                    .frame(maxWidth: 600)
            }
            HStack(alignment: .top, spacing: 16) {
                field(label: settingsStore.localized("companyProfile.field.phone", defaultValue: "Telefon")) {
                    ProWorkMaskedTextField(
                        placeholder: "(5__) ___ __ __",
                        text: phoneBinding,
                        mask: "(###) ### ## ##"
                    )
                        .frame(maxWidth: 240)
                }
                field(label: settingsStore.localized("companyProfile.field.email", defaultValue: "E-posta")) {
                    ProWorkTextField(placeholder: settingsStore.localized("companyProfile.field.email.placeholder", defaultValue: "info@…"), text: bindOptional(\.email))
                        .frame(maxWidth: 280)
                }
                Spacer()
            }
            field(label: settingsStore.localized("companyProfile.field.website", defaultValue: "Web Sitesi")) {
                ProWorkTextField(placeholder: settingsStore.localized("companyProfile.field.website.placeholder", defaultValue: "https://…"), text: bindOptional(\.website))
                    .frame(maxWidth: 480)
            }
        }
    }

    private var paymentFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(label: settingsStore.localized("companyProfile.field.paymentTerms", defaultValue: "Vade Süresi (gün)")) {
                HStack {
                    Stepper(value: $profile.paymentTermsDays, in: 0...180) {
                        Text(String(format: settingsStore.localized("companyProfile.unit.days", defaultValue: "%d gün"), profile.paymentTermsDays))
                            .proWorkTextStyle(.callout)
                            .frame(minWidth: 80, alignment: .leading)
                    }
                    .labelsHidden()
                    Text(String(format: settingsStore.localized("companyProfile.unit.days", defaultValue: "%d gün"), profile.paymentTermsDays))
                        .proWorkTextStyle(.callout)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Helpers

    private func field<Content: View>(
        label: String,
        required: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .proWorkTextStyle(.caption, weight: .medium)
                    .foregroundStyle(.secondary)
                if required {
                    Text("*").foregroundStyle(.red)
                }
            }
            content()
        }
    }

    private func bindOptional(_ keyPath: WritableKeyPath<CompanyProfile, String?>) -> Binding<String> {
        Binding(
            get: { profile[keyPath: keyPath] ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                profile[keyPath: keyPath] = trimmed.isEmpty ? nil : value
            }
        )
    }

    private var taxNumberBinding: Binding<String> {
        Binding(
            get: { profile.taxNumber ?? "" },
            set: { value in
                let normalized = normalizeTaxNumber(value)
                profile.taxNumber = normalized.isEmpty ? nil : normalized
            }
        )
    }

    private var phoneBinding: Binding<String> {
        Binding(
            get: { profile.phone ?? "" },
            set: { value in
                let formatted = normalizedPhoneValue(value)
                profile.phone = formatted.isEmpty ? nil : formatted
            }
        )
    }

    // MARK: - Persistence

    private func load() {
        do {
            if let existing = try repository.fetch(organizationId: BuiltInOrganizationId.default) {
                profile = normalizedProfile(existing)
            } else {
                profile = normalizedProfile(CompanyProfile(
                    legalName: settingsStore.localized("companyProfile.default.legalName", defaultValue: "Şirketinizin Adı"),
                    organizationId: BuiltInOrganizationId.default
                ))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        profile = normalizedProfile(profile)
        let cleanName = profile.legalName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            errorMessage = settingsStore.localized("companyProfile.error.legalNameRequired", defaultValue: "Ünvan zorunludur.")
            return
        }

        if let taxNumber = profile.taxNumber,
           (taxNumber.count > 11 || !taxNumber.allSatisfy(\.isNumber)) {
            errorMessage = settingsStore.localized("companyProfile.error.taxNumberLength", defaultValue: "Vergi no en fazla 11 haneli olmalı ve sadece rakam içermelidir.")
            return
        }

        if let phone = profile.phone, !phone.isEmpty {
            let digits = phone.filter(\.isNumber)
            guard digits.count == 10, phone == formatPhoneNumber(digits) else {
                errorMessage = settingsStore.localized("companyProfile.error.phoneFormat", defaultValue: "Telefon numarası `(000) 000 00 00` formatında 10 haneli olmalı.")
                return
            }
            profile.phone = formatPhoneNumber(digits)
        }

        profile.legalName = cleanName
        profile.updatedAt = Date()

        do {
            try repository.upsert(profile)
            errorMessage = nil
            savedNotice = settingsStore.localized("common.saved", defaultValue: "Kaydedildi.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if savedNotice == settingsStore.localized("common.saved", defaultValue: "Kaydedildi.") { savedNotice = nil }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleLogoImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let data = try readImportedImageData(from: url)
                profile.logoData = data
                errorMessage = nil
            } catch {
                errorMessage = String(format: settingsStore.localized("companyProfile.error.logoRead", defaultValue: "Logo okunamadı: %@"), error.localizedDescription)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func readImportedImageData(from url: URL) throws -> Data {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try Data(contentsOf: url)
    }

    private func normalizedProfile(_ value: CompanyProfile) -> CompanyProfile {
        var normalized = value
        let taxNumber = normalizeTaxNumber(value.taxNumber ?? "")
        normalized.taxNumber = taxNumber.isEmpty ? nil : taxNumber
        normalized.phone = normalizedPhoneValue(value.phone ?? "").nilIfEmpty
        return normalized
    }

    private func normalizeTaxNumber(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(11))
    }

    private func normalizedPhoneValue(_ value: String) -> String {
        let digits = String(value.filter(\.isNumber).prefix(10))
        return formatPhoneNumber(digits)
    }

    private func formatPhoneNumber(_ digits: String) -> String {
        guard !digits.isEmpty else { return "" }

        var result = ""
        let characters = Array(digits)

        result.append("(")
        for index in 0..<min(characters.count, 3) {
            result.append(characters[index])
        }

        if characters.count >= 3 {
            result.append(")")
        }
        if characters.count > 3 {
            result.append(" ")
            for index in 3..<min(characters.count, 6) {
                result.append(characters[index])
            }
        }
        if characters.count > 6 {
            result.append(" ")
            for index in 6..<min(characters.count, 8) {
                result.append(characters[index])
            }
        }
        if characters.count > 8 {
            result.append(" ")
            for index in 8..<min(characters.count, 10) {
                result.append(characters[index])
            }
        }

        return result
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
