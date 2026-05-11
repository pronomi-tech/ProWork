//
//  ProWorkFormHeader.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct ProWorkFormHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String = "doc.text",
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                   .proWorkFont(size: 24, weight: .semibold)
                    .foregroundStyle(.blue)
                    .proWorkFrame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .proWorkTextStyle(.title2)
                        .bold()

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .proWorkTextStyle(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                trailing
            }

            Divider()
        }
        .proWorkFrame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ProWorkFormHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String = "doc.text"
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = EmptyView()
    }
}
