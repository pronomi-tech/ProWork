//  NoticeScheduler.swift
//  ProWork
//  Created by Pronomi.
// /: shared "save toast" auto-dismiss helper. Pulled
//  out of BillingRunsViewModel so ExchangeRatesViewModel (and any
//  future VM) gets the same race-resistant behaviour:
//    • previous in-flight dismissal cancels when a new notice arrives,
//      so a quick succession of saves doesn't clear a notice that just
//      replaced it (matching-string race);
//    • a generation counter — not a string compare — gates the
//      clearance, so two notices with identical text don't clobber
// each other's lifetime.
//  Caller binds the helper to its `@Published var notice: String?`
//  via a setter closure that runs on the main actor.

import Foundation

@MainActor
final class NoticeScheduler {
    /// Length of time a notice is held before being cleared. Default
    /// matches the previous BillingRunsViewModel constant.
    let duration: UInt64

    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?

    init(duration: UInt64 = 2_000_000_000) {
        self.duration = duration
    }

    /// Shows `message` immediately via `setter(message)` and schedules
    /// a clear-to-nil after `duration`. The clear only fires if no new
    /// `show(_:setter:)` was invoked in the meantime — the generation
    /// counter survives identical-message replacements.
    func show(_ message: String, setter: @MainActor @escaping (String?) -> Void) {
        setter(message)
        generation &+= 1
        let scheduledGeneration = generation
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.duration)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.generation == scheduledGeneration else { return }
                setter(nil)
            }
        }
    }

    /// Cancels any in-flight clear. Useful when the owner is torn down
    /// or wants to force-keep the notice.
    func cancel() {
        task?.cancel()
        task = nil
    }
}
