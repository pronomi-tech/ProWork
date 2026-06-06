//  BillingActionButton.swift
//  ProWork
//  Extracted from BillingRunsView. Single .bordered
//  action button with an optional in-flight ProgressView. The
//  exportCard reuses this shape for both the preview button (loading
//  state) and the per-format export buttons (no loading state); pulling
//  them through one helper keeps the visual language consistent and a
//  future change centralized.

import SwiftUI

struct BillingActionButton: View {
    let title: String
    let systemImage: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 30, height: 30)
            } else {
                ProWorkButtonLabel(title: title, systemImage: systemImage, minHeight: 30)
            }
        }
        .buttonStyle(.bordered)
        .disabled(isLoading)
    }
}
