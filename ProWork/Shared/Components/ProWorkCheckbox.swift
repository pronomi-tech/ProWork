//  ProWorkCheckbox.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct ProWorkCheckbox: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let title: String
    @Binding var isOn: Bool
    let isDisabled: Bool
    let boxSize: CGFloat

    init(
        _ title: String = "",
        isOn: Binding<Bool>,
        isDisabled: Bool = false,
        boxSize: CGFloat = 22
    ) {
        self.title = title
        self._isOn = isOn
        self.isDisabled = isDisabled
        self.boxSize = boxSize
    }

    var body: some View {
        Button {
            guard !isDisabled else {
                return
            }

            isOn.toggle()
        } label: {
            HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                checkboxBox

                if !title.isEmpty {
                    Text(title)
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(isDisabled ? .secondary : .primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private var checkboxBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(6, using: settingsStore))
                .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.12))

            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(6, using: settingsStore))
                .stroke(
                    isOn ? Color.accentColor : Color.secondary.opacity(0.28),
                    lineWidth: 1
                )

            if isOn {
                Image(systemName: "checkmark")
                    .proWorkFont(size: 14, weight: .bold)
                    .foregroundStyle(.white)
            }
        }
        .frame(
            width: ProWorkLayout.scaled(boxSize, using: settingsStore),
            height: ProWorkLayout.scaled(boxSize, using: settingsStore)
        )
    }
}
