//
//  ProWorkFormFooter.swift
//  ProWork
//
//  Created by Pronomi.
//
//  TÜM düzenleme/oluşturma form'larında alt buton barı standardı.
//  Vazgeç ve Kaydet butonları aynı ebatta:
//      ProWorkButtonLabel + minHeight 32 + .controlSize(.large)
//      Vazgeç: .bordered, Kaydet: .borderedProminent
//

import SwiftUI

/// İki butonlu (Vazgeç + Kaydet) standart form footer.
struct ProWorkFormFooter: View {
    let onCancel: () -> Void
    let onSave: () -> Void
    var cancelTitle: String = ""
    var cancelSystemImage: String = "xmark"
    var saveTitle: String = ""
    var saveSystemImage: String = "checkmark"
    var saveDisabled: Bool = false

    private var effectiveCancelTitle: String {
        cancelTitle.isEmpty
            ? ProWorkLocalizer.shared.string("common.cancel", defaultValue: "Vazgeç")
            : cancelTitle
    }

    private var effectiveSaveTitle: String {
        saveTitle.isEmpty
            ? ProWorkLocalizer.shared.string("common.save", defaultValue: "Kaydet")
            : saveTitle
    }

    var body: some View {
        HStack(spacing: 12) {
            Spacer()

            Button {
                onCancel()
            } label: {
                ProWorkButtonLabel(
                    title: effectiveCancelTitle,
                    systemImage: cancelSystemImage,
                    minHeight: 32
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)

            Button {
                onSave()
            } label: {
                ProWorkButtonLabel(
                    title: effectiveSaveTitle,
                    systemImage: saveSystemImage,
                    minHeight: 32
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(saveDisabled)
        }
    }
}

/// Tek butonlu (Kapat / OK gibi) standart form footer.
struct ProWorkFormSingleFooter: View {
    let onPrimary: () -> Void
    var title: String = ""
    var systemImage: String = "xmark"
    var isProminent: Bool = false

    private var effectiveTitle: String {
        title.isEmpty
            ? ProWorkLocalizer.shared.string("common.close", defaultValue: "Kapat")
            : title
    }

    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            if isProminent {
                Button {
                    onPrimary()
                } label: {
                    ProWorkButtonLabel(title: effectiveTitle, systemImage: systemImage, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    onPrimary()
                } label: {
                    ProWorkButtonLabel(title: effectiveTitle, systemImage: systemImage, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Form içinde hata mesajı banner'ı.
struct ProWorkFormError: View {
    let message: String?

    var body: some View {
        Color.clear
            .frame(height: 0)
            .proWorkToastNotifications(errorMessage: message)
    }
}
