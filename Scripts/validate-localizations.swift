// validate-localizations.swift
// ProWork lokalizasyon kontrol scripti.
// Tüm `.lproj/Localizable.strings` dosyalarını okur, her anahtar için
// "%d", "%@", "%lld", "%1$@" gibi placeholder'ların sayısını / sırasını
// karşılaştırır. tr ve en arasında uyumsuzluk bulursa exit 1 ile patlar.
// Kullanım:
//   swift Scripts/validate-localizations.swift ProWork
// CI'da pre-commit / pre-merge adımı olarak çağrılır.

import Foundation

guard CommandLine.arguments.count >= 2 else {
    print("usage: swift Scripts/validate-localizations.swift <project-root>")
    exit(2)
}

let projectRoot = CommandLine.arguments[1]
let fileManager = FileManager.default

// `.lproj` dizinlerini bul
let projectURL = URL(fileURLWithPath: projectRoot, isDirectory: true)
guard let enumerator = fileManager.enumerator(at: projectURL, includingPropertiesForKeys: nil) else {
    print("error: cannot enumerate \(projectRoot)")
    exit(2)
}

var lprojPaths: [URL] = []
for case let url as URL in enumerator {
    if url.pathExtension == "lproj" {
        lprojPaths.append(url)
    }
}

guard !lprojPaths.isEmpty else {
    print("error: no .lproj directories found under \(projectRoot)")
    exit(2)
}

func parseStrings(at url: URL) throws -> [String: String] {
    let content = try String(contentsOf: url, encoding: .utf8)
    var result: [String: String] = [:]
    // Çok basit "key" = "value"; pattern. Yorum / multiline değerleri
    // desteklemez — Apple .strings dosyaları tek satır ve quoted şeklinde.
    let pattern = #"^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$"#
    let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    let ns = content as NSString
    let range = NSRange(location: 0, length: ns.length)
    regex.enumerateMatches(in: content, range: range) { match, _, _ in
        guard let match,
              match.numberOfRanges == 3 else { return }
        let key = ns.substring(with: match.range(at: 1))
        let value = ns.substring(with: match.range(at: 2))
        result[key] = value
    }
    return result
}

// "%d", "%@", "%1$@", "%lld", "%2$d" vb. placeholder'ları sıralı listele.
func placeholders(in value: String) -> [String] {
    let pattern = #"%(?:\d+\$)?[@dDuUxXoOfeEgGcCsSpaA%]|%(?:\d+\$)?l{1,2}[dDuUxXoO]"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = value as NSString
    let range = NSRange(location: 0, length: ns.length)
    return regex.matches(in: value, range: range).map { ns.substring(with: $0.range) }
}

// Her .lproj için strings dosyalarını oku.
var stringsByLocale: [String: [String: String]] = [:]
for lproj in lprojPaths {
    let stringsURL = lproj.appendingPathComponent("Localizable.strings")
    guard fileManager.fileExists(atPath: stringsURL.path) else { continue }
    do {
        let parsed = try parseStrings(at: stringsURL)
        let locale = lproj.deletingPathExtension().lastPathComponent
        stringsByLocale[locale] = parsed
    } catch {
        print("error: cannot read \(stringsURL.path): \(error.localizedDescription)")
        exit(2)
    }
}

guard let baseLocale = stringsByLocale.keys.sorted().first,
      let baseStrings = stringsByLocale[baseLocale] else {
    print("error: no usable .lproj/Localizable.strings found")
    exit(2)
}

var problems: [String] = []
for (locale, strings) in stringsByLocale where locale != baseLocale {
    for (key, baseValue) in baseStrings {
        guard let translation = strings[key] else {
            problems.append("\(locale): missing key '\(key)'")
            continue
        }
        let basePlaceholders = placeholders(in: baseValue)
        let trPlaceholders = placeholders(in: translation)
        if basePlaceholders != trPlaceholders {
            problems.append(
                "\(locale): placeholder mismatch for '\(key)'; base=\(basePlaceholders) target=\(trPlaceholders)"
            )
        }
    }
    for key in strings.keys where baseStrings[key] == nil {
        problems.append("\(locale): orphan key '\(key)' (not in \(baseLocale))")
    }
}

if problems.isEmpty {
    print("Localizations OK (\(baseStrings.count) keys × \(stringsByLocale.count) locales)")
    exit(0)
} else {
    print("Found \(problems.count) localization issue(s):")
    for problem in problems.prefix(50) {
        print("  - \(problem)")
    }
    if problems.count > 50 {
        print("  ... and \(problems.count - 50) more")
    }
    exit(1)
}
