//  ProWorkFormFooter.swift
//  ProWork
//  Created by Pronomi.
//  Standard footer button bar used in ALL edit/create forms.
//  Cancel and Save share the same size:
//      ProWorkButtonLabel + minHeight 32 + .controlSize(.large)
//      Cancel: .bordered, Save: .borderedProminent

import SwiftUI

/// Standard two-button (Cancel + Save) form footer.
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

            // every form footer now exposes stable
            // accessibility identifiers so UI tests and VoiceOver can
            // reach the cancel/save controls by name. Title (which
            // doubles as the visible label) feeds the VoiceOver
            // accessibilityLabel; the identifier is anchored to the
            // semantic action.
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
            .accessibilityIdentifier("prowork.formFooter.cancel")
            .accessibilityLabel(effectiveCancelTitle)

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
            .accessibilityIdentifier("prowork.formFooter.save")
            .accessibilityLabel(effectiveSaveTitle)
        }
        // macOS power users expect ⌘↩ to commit a form.
        // `keyboardShortcut(.defaultAction)` above already binds Return,
        // but does not include the Command modifier. A hidden button binds
        // the ⌘↩ alias so both work; it lives off-screen via clipped(),
        // keyboardShortcut still routes through the save action.
        .background(
            Button("", action: onSave)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(saveDisabled)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }
}

/// Standard single-button (Close / OK style) form footer.
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

/// Error-message banner inside a form.
struct ProWorkFormError: View {
    let message: String?

    var body: some View {
        Color.clear
            .frame(height: 0)
            .proWorkToastNotifications(errorMessage: message)
    }
}
