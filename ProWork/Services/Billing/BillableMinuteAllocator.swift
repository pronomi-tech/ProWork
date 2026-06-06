//  BillableMinuteAllocator.swift
//  ProWork
//  Created by Pronomi

import Foundation

enum BillableMinuteAllocator {
    /// Distributes the total billable minutes by duration weight.
    /// The distribution preserves the total and uses stable largest-remainder.
    static func allocate(
        durationSeconds: [Int],
        totalBillableMinutes: Int
    ) -> [Int] {
        guard totalBillableMinutes > 0, !durationSeconds.isEmpty else {
            return Array(repeating: 0, count: durationSeconds.count)
        }

        let normalizedSeconds = durationSeconds.map { max(0, $0) }
        let totalSeconds = normalizedSeconds.reduce(0, +)

        guard totalSeconds > 0 else {
            var fallback = Array(repeating: 0, count: normalizedSeconds.count)
            fallback[0] = totalBillableMinutes
            return fallback
        }

        var allocations = Array(repeating: 0, count: normalizedSeconds.count)
        var remainders: [(index: Int, remainder: Int)] = []
        var allocatedMinutes = 0

        // `seconds * totalBillableMinutes` teorik olarak
        // Can overflow `Int.max`, but practical upper bounds make that
        // impossible: a segment is at most 24h (86_400 s) and the total
        // billable minutes in an accounting period is at most
        // 31 days = 44_640 minutes → product ≈ 3.86e9, far below
        // Int64's ~9.22e18 limit. So we don't add an explicit overflow
        // guard, but if the daily duration cap ever changes this needs
        // to be revisited.
        for (index, seconds) in normalizedSeconds.enumerated() {
            let weightedSeconds = seconds * totalBillableMinutes
            let minutes = weightedSeconds / totalSeconds
            let remainder = weightedSeconds % totalSeconds
            allocations[index] = minutes
            allocatedMinutes += minutes
            remainders.append((index, remainder))
        }

        let remainingMinutes = totalBillableMinutes - allocatedMinutes
        guard remainingMinutes > 0 else {
            return allocations
        }

        let ranked = remainders.sorted { lhs, rhs in
            if lhs.remainder != rhs.remainder {
                return lhs.remainder > rhs.remainder
            }
            return lhs.index < rhs.index
        }

        for index in 0..<remainingMinutes {
            allocations[ranked[index].index] += 1
        }

        return allocations
    }
}
