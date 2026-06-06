//  ProWorkInputFields.swift
//  ProWork
//  Created by Pronomi

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
        let separator = Character(settingsStore.locale.decimalSeparator ?? ",")
        return ProWorkNumberField.sanitize(value, style: style, separator: separator)
    }

    /// extracted as a pure static helper so unit tests can
    /// exercise the locale-aware parsing/clamping logic without standing
    /// up a full SwiftUI environment with a settings store. The Style is
    /// still public-by-default since `ProWorkNumberField` itself is, but
    /// the sanitize helper is exposed internally for testing.
    static func sanitize(
        _ value: String,
        style: Style,
        separator: Character
    ) -> String {
        switch style {
        case .integer(let maxDigits):
            let digits = value.filter(\.isNumber)
            guard let maxDigits else { return digits }
            return String(digits.prefix(maxDigits))

        case .decimal(let maxFractionDigits, let maxIntegerDigits):
            let alternateSeparator: Character = separator == "," ? "." : ","
            var filtered = value.filter { $0.isNumber || $0 == separator || $0 == alternateSeparator }

            // In common locales the alternate separator is also the thousands separator
            // (tr_TR: decimal=",", thousands="."; en_US: decimal=".", thousands=",").
            // Rule: if the user has already typed a decimal, or the alternate appears
            // more than once, treat it as a thousands separator and strip it.
            // Otherwise (no decimal, exactly one alternate) the user typed the alternate
            // as a decimal → convert it to the configured decimal.
            let decimalCount = filtered.filter { $0 == separator }.count
            let alternateCount = filtered.filter { $0 == alternateSeparator }.count
            if decimalCount == 0 && alternateCount == 1 {
                filtered = filtered.replacingOccurrences(of: String(alternateSeparator), with: String(separator))
            } else {
                filtered = filtered.replacingOccurrences(of: String(alternateSeparator), with: "")
            }

            // If there's more than one decimal separator, ignore everything after the first.
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
            if parts.count > 1 && maxFractionDigits > 0 {
                result.append(separator)
                result.append(String(parts[1].prefix(maxFractionDigits)))
            }

            // defensive final clamp. The split-based path
            // above already trims, but a paste containing an unusual mix of
            // separators (multiple decimals + alternates) had edge cases
            // where the fractional tail could survive longer than the
            // configured maxFractionDigits. Re-clamp the final string by
            // searching for the separator and truncating the tail to the
            // configured digit count; integer-only configs (max==0) lose
            // any trailing separator too.
            if let separatorIndex = result.firstIndex(of: separator) {
                let fractionStart = result.index(after: separatorIndex)
                let fractionTail = result[fractionStart...]
                if fractionTail.count > maxFractionDigits {
                    let clampedEnd = result.index(fractionStart, offsetBy: maxFractionDigits)
                    result = String(result[..<clampedEnd])
                }
                if maxFractionDigits == 0 {
                    result = String(result[..<separatorIndex])
                }
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
