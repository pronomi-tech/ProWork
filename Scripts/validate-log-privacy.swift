// validate-log-privacy.swift
// privacy linter for ProWorkLog call sites.
// Scans every .swift file under the given root and reports any
// `ProWorkLog.<category>.<level>("...\(expr)...")` invocation whose
// interpolated expressions do not carry an explicit `privacy:` marker.
// Forcing the call site to make a privacy decision keeps tenant /
// customer / financial values out of macOS Console exports.
// Usage:
//   swift Scripts/validate-log-privacy.swift ProWork
// Wired into the project as a Run Script build phase that runs in
// parallel with validate-localizations.swift.

import Foundation

guard CommandLine.arguments.count >= 2 else {
    print("usage: swift Scripts/validate-log-privacy.swift <project-root>")
    exit(2)
}

let projectRoot = CommandLine.arguments[1]
let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: projectRoot, isDirectory: true)

guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: nil) else {
    print("error: cannot enumerate \(projectRoot)")
    exit(2)
}

// Match a ProWorkLog call. We accept a generous span up to the closing
// paren of the first format string argument; ProWorkLog calls in the
// codebase use a single string per call, so this is enough.
let logPattern = #"ProWorkLog\.[a-zA-Z]+\.(?:debug|info|notice|warning|error|fault|critical)\(\s*"((?:[^"\\]|\\.)*)"\s*\)"#
guard let logRegex = try? NSRegularExpression(pattern: logPattern, options: [.dotMatchesLineSeparators]) else {
    print("error: log regex failed to compile")
    exit(2)
}

// Inside the captured string literal, find every `\(...)` interpolation
// and check whether it ends with a `privacy:` marker.
let interpPattern = #"\\\(([^)]*)\)"#
guard let interpRegex = try? NSRegularExpression(pattern: interpPattern) else {
    print("error: interpolation regex failed to compile")
    exit(2)
}

var violations: [String] = []
var scanned = 0

for case let url as URL in enumerator where url.pathExtension == "swift" {
    let path = url.path
    if path.contains("/.build/") || path.contains("/DerivedData/") || path.contains("/Scripts/") {
        continue
    }
    guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
    scanned += 1
    let ns = content as NSString
    let range = NSRange(location: 0, length: ns.length)
    logRegex.enumerateMatches(in: content, range: range) { match, _, _ in
        guard let match, match.numberOfRanges == 2 else { return }
        let literal = ns.substring(with: match.range(at: 1))
        let nsLit = literal as NSString
        let litRange = NSRange(location: 0, length: nsLit.length)
        interpRegex.enumerateMatches(in: literal, range: litRange) { interp, _, _ in
            guard let interp else { return }
            let body = nsLit.substring(with: interp.range(at: 1))
            if !body.contains("privacy:") {
                // Locate the line number of the parent log call.
                let prefix = ns.substring(with: NSRange(location: 0, length: match.range.location))
                let lineNumber = prefix.filter { $0 == "\n" }.count + 1
                violations.append("\(path):\(lineNumber): ProWorkLog interpolation missing privacy marker → \\(\(body))")
            }
        }
    }
}

if violations.isEmpty {
    print("Log privacy OK (\(scanned) files scanned)")
    exit(0)
}

print("Found \(violations.count) ProWorkLog privacy issue(s):")
for v in violations.prefix(50) {
    print("  - \(v)")
}
if violations.count > 50 {
    print("  ... and \(violations.count - 50) more")
}
exit(1)
