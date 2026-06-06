//  ProWorkConfirmation.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct ProWorkConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    let role: ButtonRole?
    let onConfirm: () -> Void

    init(
        title: String,
        message: String,
        confirmTitle: String? = nil,
        cancelTitle: String? = nil,
        role: ButtonRole? = nil,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle ?? ProWorkLocalizer.shared.string("common.confirm", defaultValue: "Onayla")
        self.cancelTitle = cancelTitle ?? ProWorkLocalizer.shared.string("common.cancel", defaultValue: "Vazgeç")
        self.role = role
        self.onConfirm = onConfirm
    }
}

extension View {
    func proWorkConfirmationDialog(
        _ confirmation: Binding<ProWorkConfirmation?>
    ) -> some View {
        self.confirmationDialog(
            confirmation.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: {
                    confirmation.wrappedValue != nil
                },
                set: { newValue in
                    if !newValue {
                        confirmation.wrappedValue = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let current = confirmation.wrappedValue {
                Button(current.confirmTitle, role: current.role) {
                    let action = current.onConfirm
                    confirmation.wrappedValue = nil
                    action()
                }

                Button(current.cancelTitle, role: .cancel) {
                    confirmation.wrappedValue = nil
                }
            }
        } message: {
            if let current = confirmation.wrappedValue {
                Text(current.message)
            }
        }
    }
}
