//  MinimumWindowApplier.swift
//  ProWork
//  Created by Pronomi.
//  Spec §4 — Minimum billing window.
//  The previous comment used the term "sliding window", but the
//  implementation does ceil division. The difference: a true sliding
//  window shifts bands based on the session start time (a job that
//  starts at 10:30 sees the 11:30, 12:30 bands), while this formula
//  only rounds the total minutes up to a multiple of the window — it
//  computes "how many windows' worth of duration", not "how many bands".
//  There is no alignment or start-time concept.
//  Formula:
//      billable_minutes = ceil(actual_minutes / window_minutes) * window_minutes
//  Pure function. All computation logic in one place. UI and repositories call this.

import Foundation

enum MinimumWindowApplier {
    /// Rounds the given actual duration up to the minimum-window rule.
    /// - Parameters:
    ///   - actualMinutes: Actual work duration (minutes).
    ///   - windowMinutes: Minimum window width (minutes). No rounding if 0 or negative.
    /// - Returns: Billable duration (minutes).
    static func apply(actualMinutes: Int, windowMinutes: Int?) -> Int {
        guard let window = windowMinutes, window > 0 else {
            return max(0, actualMinutes)
        }
        if actualMinutes <= 0 { return 0 }
        let nWindows = (actualMinutes + window - 1) / window  // ceiling division
        return nWindows * window
    }

    /// Rounds an exact second duration to the configured minute window.
    /// Only the minimum-window boundary is rounded; the source duration is not
    /// converted to whole minutes first.
    static func applySeconds(actualSeconds: Int, windowMinutes: Int?) -> Int {
        guard actualSeconds > 0 else { return 0 }
        guard let windowMinutes, windowMinutes > 0 else { return actualSeconds }
        let windowSeconds = windowMinutes * 60
        let windowCount = (actualSeconds + windowSeconds - 1) / windowSeconds
        return windowCount * windowSeconds
    }
}
