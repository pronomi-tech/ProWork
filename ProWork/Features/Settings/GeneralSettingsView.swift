//
//  GeneralSettingsView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @State private var statuses: [TodoStatus] = []

    private let statusRepository = TodoStatusRepository()

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("general.title", defaultValue: "Genel Ayarlar"),
            subtitle: settingsStore.localized("general.subtitle", defaultValue: "Uygulama genelinde kullanılacak tarih, saat ve yazı boyutu tercihlerini yönetin.")
        ) {
            settingsCard
            previewCard
        }
        .onAppear(perform: loadStatuses)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(18, using: settingsStore)) {
            sectionTitle(settingsStore.localized("general.section.formatting", defaultValue: "Biçimlendirme"))

            settingRow(
                title: settingsStore.localized("general.row.language.title", defaultValue: "Uygulama Dili"),
                subtitle: settingsStore.localized("general.row.language.subtitle", defaultValue: "Arayüz ve yerelleştirme tercihleri için temel dil.")
            ) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("general.row.language.placeholder", defaultValue: "Dil seçin"),
                    items: AppLanguage.allCases,
                    selectedId: languageBinding,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "globe",
                    itemTitle: { option in
                        option.title
                    },
                    itemSubtitle: { option in
                        option.localeIdentifier
                    },
                    itemColor: { _ in
                        nil
                    },
                    matchesSearch: { option, searchText in
                        option.title.localizedCaseInsensitiveContains(searchText) ||
                        option.localeIdentifier.localizedCaseInsensitiveContains(searchText)
                    }
                )
                .proWorkFrame(width: 280)
            }

            settingRow(
                title: settingsStore.localized("general.row.dateFormat.title", defaultValue: "Tarih Formatı"),
                subtitle: settingsStore.localized("general.row.dateFormat.subtitle", defaultValue: "Tarih alanlarında kullanılacak görünüm.")
            ) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("general.row.dateFormat.placeholder", defaultValue: "Tarih formatı seçin"),
                    items: AppDateFormatOption.allCases,
                    selectedId: dateFormatBinding,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "calendar",
                    itemTitle: { option in
                        option.title(locale: settingsStore.locale)
                    },
                    itemSubtitle: { option in
                        option.rawValue
                    },
                    itemColor: { _ in
                        nil
                    },
                    matchesSearch: { option, searchText in
                        option.title(locale: settingsStore.locale).localizedCaseInsensitiveContains(searchText) ||
                        option.rawValue.localizedCaseInsensitiveContains(searchText)
                    }
                )
                .proWorkFrame(width: 280)
            }

            settingRow(
                title: settingsStore.localized("general.row.timeFormat.title", defaultValue: "Saat Formatı"),
                subtitle: settingsStore.localized("general.row.timeFormat.subtitle", defaultValue: "Saat alanlarında kullanılacak görünüm.")
            ) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("general.row.timeFormat.placeholder", defaultValue: "Saat formatı seçin"),
                    items: AppTimeFormatOption.allCases,
                    selectedId: timeFormatBinding,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "clock",
                    itemTitle: { option in
                        option.title(locale: settingsStore.locale)
                    },
                    itemSubtitle: { option in
                        option.rawValue
                    },
                    itemColor: { _ in
                        nil
                    },
                    matchesSearch: { option, searchText in
                        option.title(locale: settingsStore.locale).localizedCaseInsensitiveContains(searchText) ||
                        option.rawValue.localizedCaseInsensitiveContains(searchText)
                    }
                )
                .proWorkFrame(width: 280)
            }

            settingRow(
                title: settingsStore.localized("general.row.dateTimeFormat.title", defaultValue: "Tarih + Saat Formatı"),
                subtitle: settingsStore.localized("general.row.dateTimeFormat.subtitle", defaultValue: "Liste ve özetlerde kullanılacak birleşik görünüm.")
            ) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("general.row.dateTimeFormat.placeholder", defaultValue: "Tarih + saat formatı seçin"),
                    items: AppDateTimeFormatOption.allCases,
                    selectedId: dateTimeFormatBinding,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "calendar.badge.clock",
                    itemTitle: { option in
                        option.title(locale: settingsStore.locale)
                    },
                    itemSubtitle: { option in
                        option.rawValue
                    },
                    itemColor: { _ in
                        nil
                    },
                    matchesSearch: { option, searchText in
                        option.title(locale: settingsStore.locale).localizedCaseInsensitiveContains(searchText) ||
                        option.rawValue.localizedCaseInsensitiveContains(searchText)
                    }
                )
                .proWorkFrame(width: 320)
            }

            Divider()

            sectionTitle(settingsStore.localized("general.section.appearance", defaultValue: "Görünüm"))

            settingRow(
                title: settingsStore.localized("general.row.fontSize.title", defaultValue: "Yazı Boyutu"),
                subtitle: settingsStore.localized("general.row.fontSize.subtitle", defaultValue: "Tüm ekranlarda kullanılan yazı ölçeği.")
            ) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("general.row.fontSize.placeholder", defaultValue: "Yazı boyutu seçin"),
                    items: AppFontSizeOption.allCases,
                    selectedId: fontSizeRawBinding,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "textformat.size",
                    itemTitle: { option in
                        fontSizeTitle(for: option)
                    },
                    itemSubtitle: { option in
                        "\(Int(option.scale * 100))%"
                    },
                    itemColor: { _ in
                        nil
                    },
                    matchesSearch: { option, searchText in
                        fontSizeTitle(for: option).localizedCaseInsensitiveContains(searchText) ||
                        option.rawValue.localizedCaseInsensitiveContains(searchText)
                    }
                )
                .proWorkFrame(width: 280)
            }

            Divider()

            sectionTitle(settingsStore.localized("general.section.automation", defaultValue: "Otomasyon"))

            settingRow(
                title: settingsStore.localized("general.row.launchAtLogin.title", defaultValue: "Bilgisayar Açılışında Başlat"),
                subtitle: settingsStore.localized("general.row.launchAtLogin.subtitle", defaultValue: "Kullanıcı oturumu açıldığında ProWork otomatik başlatılır.")
            ) {
                Toggle("", isOn: launchAtLoginEnabledBinding)
                    .labelsHidden()
            }

            if settingsStore.settings.launchAtLoginEnabled {
                settingRow(
                    title: settingsStore.localized("general.row.openMainWindowOnLaunch.title", defaultValue: "Açılışta Ana Ekranı Göster"),
                    subtitle: settingsStore.localized("general.row.openMainWindowOnLaunch.subtitle", defaultValue: "Kapalıysa uygulama arka planda başlar ve yalnızca menü barda görünür.")
                ) {
                    Toggle("", isOn: openMainWindowOnLaunchBinding)
                        .labelsHidden()
                }
            }

            settingRow(
                title: settingsStore.localized("general.row.menuBarEnabled.title", defaultValue: "Menü Bar Hızlı Takip"),
                subtitle: settingsStore.localized("general.row.menuBarEnabled.subtitle", defaultValue: "Üst menü çubuğunda hızlı başlat/durdur menüsünü gösterir.")
            ) {
                Toggle("", isOn: menuBarEnabledBinding)
                    .labelsHidden()
            }

            if settingsStore.settings.menuBarEnabled {
                Divider()

                VStack(alignment: .leading, spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
                    Text(settingsStore.localized("general.row.menuBarStatuses.title", defaultValue: "Menü Barda Gösterilecek Statüler"))
                        .proWorkTextStyle(.callout, weight: .medium)

                    Text(settingsStore.localized("general.row.menuBarStatuses.subtitle", defaultValue: "Hiç seçim yoksa süre başlatabilen tüm aktif statüler kullanılır."))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)

                    if statuses.isEmpty {
                        Text(settingsStore.localized("general.row.menuBarStatuses.empty", defaultValue: "Aktif statü bulunamadı."))
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: ProWorkLayout.scaled(180, using: settingsStore))),
                            ],
                            alignment: .leading,
                            spacing: ProWorkLayout.scaled(8, using: settingsStore)
                        ) {
                            ForEach(statuses) { status in
                                ProWorkCheckbox(
                                    status.name,
                                    isOn: menuBarStatusBinding(for: status.id)
                                )
                            }
                        }
                    }
                }

                Divider()
            }

            settingRow(
                title: settingsStore.localized("general.row.idleAutoStop.title", defaultValue: "Boşta Kalınca Otomatik Durdur"),
                subtitle: settingsStore.localized("general.row.idleAutoStop.subtitle", defaultValue: "Bilgisayarda işlem yapılmadığında aktif çalışmayı otomatik kapatır.")
            ) {
                Toggle("", isOn: idleAutoStopEnabledBinding)
                    .labelsHidden()
            }

            if settingsStore.settings.idleAutoStopEnabled {
                settingRow(
                    title: settingsStore.localized("general.row.idleAutoStopMinutes.title", defaultValue: "Boşta Kalma Süresi"),
                    subtitle: settingsStore.localized("general.row.idleAutoStopMinutes.subtitle", defaultValue: "Bu süreden sonra aktif çalışma otomatik durdurulur.")
                ) {
                    Stepper(
                        value: idleAutoStopMinutesBinding,
                        in: 1...120
                    ) {
                        Text("\(settingsStore.settings.idleAutoStopMinutes) \(settingsStore.localized("general.unit.minute", defaultValue: "dk"))")
                            .proWorkTextStyle(.callout)
                            .frame(width: 72, alignment: .trailing)
                    }
                    .frame(width: 160)
                }
            }
        }
        .padding(ProWorkLayout.scaled(18, using: settingsStore))
        .frame(maxWidth: ProWorkLayout.scaled(820, using: settingsStore), alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(16, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(16, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            sectionTitle(settingsStore.localized("general.section.preview", defaultValue: "Önizleme"))

            HStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
                previewItem(
                    title: settingsStore.localized("general.preview.date", defaultValue: "Tarih"),
                    value: settingsStore.formatDate(Date()),
                    systemImage: "calendar"
                )

                previewItem(
                    title: settingsStore.localized("general.preview.time", defaultValue: "Saat"),
                    value: settingsStore.formatTime(Date()),
                    systemImage: "clock"
                )

                previewItem(
                    title: settingsStore.localized("general.preview.dateTime", defaultValue: "Tarih + Saat"),
                    value: settingsStore.formatDateTime(Date()),
                    systemImage: "calendar.badge.clock"
                )
            }
        }
        .padding(ProWorkLayout.scaled(18, using: settingsStore))
        .frame(maxWidth: ProWorkLayout.scaled(820, using: settingsStore), alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(16, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(16, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .proWorkTextStyle(.headline)
    }

    private func settingRow<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(3, using: settingsStore)) {
                Text(title)
                    .proWorkTextStyle(.callout, weight: .medium)

                Text(subtitle)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            content()
        }
        .proWorkFrame(minHeight: 52)
        .frame(maxWidth: .infinity)
    }

    private func previewItem(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Image(systemName: systemImage)
                .proWorkFont(size: 18)
                .foregroundStyle(.blue)
                .frame(width: ProWorkLayout.scaled(22, using: settingsStore))

            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(3, using: settingsStore)) {
                Text(title)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .proWorkTextStyle(.headline)
                    .monospacedDigit()
            }
        }
        .padding(ProWorkLayout.scaled(14, using: settingsStore))
        .frame(width: ProWorkLayout.scaled(235, using: settingsStore), alignment: .leading)
        .background(.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore)))
    }

    private func fontSizeTitle(for option: AppFontSizeOption) -> String {
        switch option {
        case .small:
            return settingsStore.localized("fontSize.small", defaultValue: "Küçük")
        case .normal:
            return settingsStore.localized("fontSize.normal", defaultValue: "Normal")
        case .large:
            return settingsStore.localized("fontSize.large", defaultValue: "Büyük")
        case .extraLarge:
            return settingsStore.localized("fontSize.extraLarge", defaultValue: "Çok Büyük")
        }
    }

    private var dateFormatBinding: Binding<String> {
        Binding(
            get: {
                settingsStore.settings.dateFormat
            },
            set: { newValue in
                settingsStore.updateDateFormat(newValue)
            }
        )
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: {
                settingsStore.settings.language.rawValue
            },
            set: { newValue in
                guard let option = AppLanguage(rawValue: newValue) else {
                    return
                }

                settingsStore.updateLanguage(option)
            }
        )
    }

    private var timeFormatBinding: Binding<String> {
        Binding(
            get: {
                settingsStore.settings.timeFormat
            },
            set: { newValue in
                settingsStore.updateTimeFormat(newValue)
            }
        )
    }

    private var dateTimeFormatBinding: Binding<String> {
        Binding(
            get: {
                settingsStore.settings.dateTimeFormat
            },
            set: { newValue in
                settingsStore.updateDateTimeFormat(newValue)
            }
        )
    }

    private var fontSizeRawBinding: Binding<String> {
        Binding(
            get: {
                settingsStore.settings.fontSize.rawValue
            },
            set: { newValue in
                guard let option = AppFontSizeOption(rawValue: newValue) else {
                    return
                }

                settingsStore.updateFontSize(option)
            }
        )
    }

    private var menuBarEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.menuBarEnabled },
            set: { settingsStore.updateMenuBarEnabled($0) }
        )
    }

    private var launchAtLoginEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.launchAtLoginEnabled },
            set: { settingsStore.updateLaunchAtLoginEnabled($0) }
        )
    }

    private var openMainWindowOnLaunchBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.openMainWindowOnLaunch },
            set: { settingsStore.updateOpenMainWindowOnLaunch($0) }
        )
    }

    private var idleAutoStopEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.idleAutoStopEnabled },
            set: { settingsStore.updateIdleAutoStopEnabled($0) }
        )
    }

    private var idleAutoStopMinutesBinding: Binding<Int> {
        Binding(
            get: { settingsStore.settings.idleAutoStopMinutes },
            set: { settingsStore.updateIdleAutoStopMinutes($0) }
        )
    }

    private func menuBarStatusBinding(for statusId: String) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings.menuBarStatusIds.contains(statusId) },
            set: { isSelected in
                var ids = settingsStore.settings.menuBarStatusIds
                if isSelected {
                    if !ids.contains(statusId) {
                        ids.append(statusId)
                    }
                } else {
                    ids.removeAll { $0 == statusId }
                }
                settingsStore.updateMenuBarStatusIds(ids)
            }
        )
    }

    private func loadStatuses() {
        let loadedStatuses = (try? statusRepository.fetchAll()) ?? []
        statuses = loadedStatuses
            .filter { $0.isActive && $0.startsTimer }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}
