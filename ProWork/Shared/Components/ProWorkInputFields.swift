//
//  ProWorkInputFields.swift
//  ProWork
//
//  Created by Pronomi
//

import SwiftUI

struct ProWorkNumberField: View {
    enum Style {
        case integer(maxDigits: Int? = nil)
        case decimal(maxFractionDigits: Int, maxIntegerDigits: Int? = nil)
    }

    @EnvironmentObject private var settingsStore: AppSettingsStore

    let title: String
    let placeholder: String
    @Binding var text: String
    let style: Style
    let minHeight: CGFloat
    let submitLabel: SubmitLabel
    let onSubmit: (() -> Void)?

    init(
        title: String = "",
        placeholder: String,
        text: Binding<String>,
        style: Style,
        minHeight: CGFloat = 40,
        submitLabel: SubmitLabel = .done,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.style = style
        self.minHeight = minHeight
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }

    var body: some View {
        ProWorkTextField(
            title: title,
            placeholder: placeholder,
            text: sanitizedBinding,
            minHeight: minHeight,
            submitLabel: submitLabel,
            onSubmit: onSubmit,
            inputFilter: sanitize
        )
    }

    private var sanitizedBinding: Binding<String> {
        Binding(
            get: { text },
            set: { text = sanitize($0) }
        )
    }

    private func sanitize(_ value: String) -> String {
        switch style {
        case .integer(let maxDigits):
            let digits = value.filter(\.isNumber)
            guard let maxDigits else { return digits }
            return String(digits.prefix(maxDigits))

        case .decimal(let maxFractionDigits, let maxIntegerDigits):
            let separator = Character(settingsStore.locale.decimalSeparator ?? ",")
            let alternateSeparator: Character = separator == "," ? "." : ","
            var filtered = value.filter { $0.isNumber || $0 == separator || $0 == alternateSeparator }

            // Yaygın locale'larda alternate separator aynı zamanda binlik ayracıdır
            // (tr_TR: decimal=",", binlik="."; en_US: decimal=".", binlik=",").
            // Ayrımı şu kuralla yapıyoruz: kullanıcı zaten decimal yazmışsa veya alternate
            // birden fazla kez geçiyorsa, alternate binlik kabul edilip kaldırılır.
            // Aksi halde (decimal yok, alternate tam bir kez) kullanıcı alternate'i decimal
            // olarak kullanmıştır → decimal'a çevrilir.
            let decimalCount = filtered.filter { $0 == separator }.count
            let alternateCount = filtered.filter { $0 == alternateSeparator }.count
            if decimalCount == 0 && alternateCount == 1 {
                filtered = filtered.replacingOccurrences(of: String(alternateSeparator), with: String(separator))
            } else {
                filtered = filtered.replacingOccurrences(of: String(alternateSeparator), with: "")
            }

            // Birden fazla decimal separator varsa ilkinden sonrasını yok say.
            let parts = filtered.split(separator: separator, omittingEmptySubsequences: false)

            let integerPart: String
            if let rawIntegerPart = parts.first {
                if let maxIntegerDigits {
                    integerPart = String(rawIntegerPart.prefix(maxIntegerDigits))
                } else {
                    integerPart = String(rawIntegerPart)
                }
            } else {
                integerPart = ""
            }

            var result = integerPart
            if parts.count > 1 {
                result.append(separator)
                result.append(String(parts[1].prefix(maxFractionDigits)))
            }

            return result
        }
    }
}

struct ProWorkMaskedTextField: View {
    @Binding var text: String

    let title: String
    let placeholder: String
    let mask: String
    let digitToken: Character
    let minHeight: CGFloat
    let submitLabel: SubmitLabel
    let onSubmit: (() -> Void)?

    init(
        title: String = "",
        placeholder: String,
        text: Binding<String>,
        mask: String,
        digitToken: Character = "#",
        minHeight: CGFloat = 40,
        submitLabel: SubmitLabel = .done,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.mask = mask
        self.digitToken = digitToken
        self.minHeight = minHeight
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }

    var body: some View {
        ProWorkTextField(
            title: title,
            placeholder: placeholder,
            text: sanitizedBinding,
            minHeight: minHeight,
            submitLabel: submitLabel,
            onSubmit: onSubmit,
            inputFilter: sanitize
        )
    }

    private var sanitizedBinding: Binding<String> {
        Binding(
            get: { text },
            set: { text = sanitize($0) }
        )
    }

    private var maxDigits: Int {
        mask.filter { $0 == digitToken }.count
    }

    private func sanitize(_ value: String) -> String {
        let digits = String(value.filter(\.isNumber).prefix(maxDigits))
        guard !digits.isEmpty else { return "" }

        var result = ""
        var digitIndex = digits.startIndex

        for character in mask {
            if character == digitToken {
                guard digitIndex < digits.endIndex else { break }
                result.append(digits[digitIndex])
                digitIndex = digits.index(after: digitIndex)
            } else {
                guard digitIndex < digits.endIndex else { break }
                result.append(character)
            }
        }

        return result
    }
}
