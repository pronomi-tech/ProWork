//  PDFDrawingPrimitives.swift
//  ProWork
//  Created by Pronomi.
//  Stateless drawing helpers shared by `BillingPdfDocument` and
//  `PriceListQuotePdfRenderer`. Previously both classes carried byte-for-byte
//  copies of `drawText`, `measureText`, `drawRoundedRect`, and `nsColor`
//. Extract them here so a fix or tuning touches one place.
//  The methods are kept as namespaced static functions so each renderer can
//  layer its own caching / instance state on top (e.g. BillingPdfDocument's
//  measure cache wraps `measureText` for memoisation).

import AppKit
import Foundation

enum PDFDrawingPrimitives {

    /// Render `text` into `rect`, returning the actual drawn height. Uses
    /// the current `NSGraphicsContext`; callers must have set it up.
    @discardableResult
    static func drawText(
        _ text: String,
        at rect: CGRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let attributed = NSAttributedString(string: text, attributes: attributes)
        let measured = attributed.boundingRect(
            with: NSSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: ceil(measured.height)
        )
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(measured.height)
    }

    /// Word-wrapped bounding box for `text` rendered at `font` inside `width`.
    static func measureText(_ text: String, width: CGFloat, font: NSFont) -> CGSize {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]

        let rect = NSAttributedString(string: text, attributes: attributes).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    /// Fill + stroke a rounded rectangle. Pass `.clear` to skip either.
    static func drawRoundedRect(
        _ rect: CGRect,
        fill: NSColor,
        stroke: NSColor,
        radius: CGFloat
    ) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if fill != .clear {
            fill.setFill()
            path.fill()
        }
        if stroke != .clear {
            stroke.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    /// Parse a hex string into a calibrated `NSColor`. Supports CSS-style
    /// `#RGB`, `#RRGGBB`, and `#RRGGBBAA` forms (with or without the
    /// leading `#`); widened the accepted shapes so a user-
    /// supplied "#000" or an RGBA template colour both work. Returns
    /// `nil` for malformed input so callers can fall back to a brand
    /// default.
    static func nsColor(fromHex hex: String) -> NSColor? {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        let normalised: String
        switch cleaned.count {
        case 3:
            // #RGB → expand each nibble to two characters (`R` → `RR`).
            normalised = cleaned.map { "\($0)\($0)" }.joined() + "FF"
        case 6:
            normalised = cleaned + "FF"
        case 8:
            normalised = cleaned
        default:
            return nil
        }
        guard let value = UInt64(normalised, radix: 16) else { return nil }
        return NSColor(
            calibratedRed: CGFloat((value & 0xFF000000) >> 24) / 255,
            green: CGFloat((value & 0x00FF0000) >> 16) / 255,
            blue: CGFloat((value & 0x0000FF00) >> 8) / 255,
            alpha: CGFloat(value & 0x000000FF) / 255
        )
    }
}
