//  PDFLogoLoader.swift
//  ProWork
//  Created by Pronomi.
//  Loads company logo data once per PDF render, downsampled to a sensible
//  pixel cap via ImageIO. Without this, every header on every page would
//  re-decode the raw bitmap (a 20MP PNG can spike memory tens of MBs and
//  blow up the embedded PDF), and the file size would balloon (code
//  review Y6).

import AppKit
import Foundation
import ImageIO
import os

enum PDFLogoLoader {
    /// Hard ceiling on input bytes. Anything larger is rejected (we'd
    /// rather render the company name fallback than embed a 50 MB PNG).
    /// Render-time cap (2 MB) intentionally tighter than the DB-level
    /// `company_profile.logoData` CHECK (5 MB, see Migration002); a
    /// large legacy logo persisted before the render cap was added
    /// still stores but won't embed.
    static let maxInputBytes = 2 * 1024 * 1024

    /// Target maximum dimension in pixels for the downsampled thumbnail.
    /// PDF logos appear at most 200×56 pt; at 144 DPI that's ~400 px wide
    /// — 512 leaves headroom for high-DPI exports.
    static let maxPixelDimension: CGFloat = 512

    /// Structured validation result so upload UIs can surface a
    /// "too big / unreadable" message instead of letting the render-time
    /// path silently drop the logo. CompanyProfile save flows should
    /// reject `.tooLarge`/`.unreadable` before persisting; the render
    /// path keeps falling back to the company-name banner.
    enum ValidationOutcome {
        case ok
        case tooLarge(bytes: Int, limit: Int)
        case unreadable
    }

    static func validate(_ data: Data?) -> ValidationOutcome {
        guard let data, !data.isEmpty else { return .ok }
        if data.count > maxInputBytes {
            return .tooLarge(bytes: data.count, limit: maxInputBytes)
        }
        let cfData = data as CFData
        guard CGImageSourceCreateWithData(cfData, nil) != nil else {
            return .unreadable
        }
        return .ok
    }

    /// Returns the downsampled logo as an `NSImage`, or `nil` if the data
    /// is too large, missing, or unreadable. The returned image is sized
    /// in points using the source image's aspect ratio.
    static func downsampledImage(from data: Data?) -> NSImage? {
        guard let data, !data.isEmpty else { return nil }
        guard data.count <= maxInputBytes else {
            ProWorkLog.app.warning(
                "PDF logo skipped: source bytes \(data.count, privacy: .public) exceed limit \(maxInputBytes, privacy: .public)."
            )
            return nil
        }

        let cfData = data as CFData
        guard let source = CGImageSourceCreateWithData(cfData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        // Use the actual pixel dimensions of the thumbnail as the point
        // size; AppKit then scales to whatever target rect we draw into.
        let size = NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        return NSImage(cgImage: cgImage, size: size)
    }
}
