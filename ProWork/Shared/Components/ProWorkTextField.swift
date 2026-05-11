//
//  ProWorkTextField.swift
//  ProWork
//
//  Created by Pronomi.
//

import AppKit
import SwiftUI

struct ProWorkTextField: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let title: String
    let placeholder: String
    @Binding var text: String
    let axis: Axis
    let minHeight: CGFloat
    let submitLabel: SubmitLabel
    let onSubmit: (() -> Void)?
    let inputFilter: ((String) -> String)?

    init(
        title: String = "",
        placeholder: String,
        text: Binding<String>,
        axis: Axis = .horizontal,
        minHeight: CGFloat = 40,
        submitLabel: SubmitLabel = .done,
        onSubmit: (() -> Void)? = nil,
        inputFilter: ((String) -> String)? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.axis = axis
        self.minHeight = minHeight
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
        self.inputFilter = inputFilter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
            if !title.isEmpty {
                Text(title)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            inputField
                .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
                .padding(.vertical, ProWorkLayout.scaled(6, using: settingsStore))
                .frame(
                    minHeight: ProWorkLayout.scaled(minHeight, using: settingsStore),
                    alignment: .center
                )
                .background(.background.opacity(0.70))
                .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore)))
                .overlay(
                    RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore))
                        .stroke(.quaternary, lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var inputField: some View {
        let swiftUIFont = ProWorkFonts.font(
            size: 15,
            weight: .regular,
            using: settingsStore
        )
        let nsFont = NSFont.systemFont(
            ofSize: ProWorkFonts.scaledSize(15, using: settingsStore),
            weight: .regular
        )

        if axis == .horizontal, let inputFilter {
            ProWorkFilteredNSTextField(
                placeholder: placeholder,
                text: $text,
                font: nsFont,
                onSubmit: onSubmit,
                inputFilter: inputFilter
            )
        } else {
            TextField(placeholder, text: $text, axis: axis)
                .textFieldStyle(.plain)
                .font(swiftUIFont)
                .submitLabel(submitLabel)
                .onSubmit {
                    onSubmit?()
                }
        }
    }
}

private struct ProWorkFilteredNSTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let font: NSFont
    let onSubmit: (() -> Void)?
    let inputFilter: (String) -> String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, inputFilter: inputFilter)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.placeholderString = placeholder
        textField.font = font
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submit)
        textField.stringValue = inputFilter(text)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        let filtered = inputFilter(text)
        if text != filtered {
            DispatchQueue.main.async {
                text = filtered
            }
        }
        if nsView.stringValue != filtered {
            nsView.stringValue = filtered
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        if nsView.font != font {
            nsView.font = font
        }
        context.coordinator.onSubmit = onSubmit
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        var onSubmit: (() -> Void)?
        private let inputFilter: (String) -> String

        init(
            text: Binding<String>,
            onSubmit: (() -> Void)?,
            inputFilter: @escaping (String) -> String
        ) {
            self._text = text
            self.onSubmit = onSubmit
            self.inputFilter = inputFilter
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            let filtered = inputFilter(textField.stringValue)
            if textField.stringValue != filtered {
                textField.stringValue = filtered
                if let editor = textField.currentEditor() {
                    editor.selectedRange = NSRange(location: filtered.count, length: 0)
                }
            }

            if text != filtered {
                text = filtered
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            onSubmit?()
            return false
        }

        @objc func submit() {
            onSubmit?()
        }
    }
}
