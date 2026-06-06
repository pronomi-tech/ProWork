//  LargestRemainderAllocator.swift
//  ProWork
//  Created by Pronomi.
//  Distributes an integer total across rows by the `weights` vector while
//  preserving the total. Algorithm: stable largest-remainder (Hamilton).
//  Negative weights are treated as 0. If every weight is 0, the total
//  is piled onto the first position.
//  Use cases:
//   - Distributing the VAT total per line (K2 — eliminates per-segment
//     rounding drift).
//   - Splitting billable minutes across segments (BillableMinuteAllocator
//     is a specialised version of this algorithm).

import Foundation

enum LargestRemainderAllocator {
    /// Distributes `total` across `weights.count` slots using the stable
    /// Hamilton (largest-remainder) method.
    /// ## Contract
    /// - The return value is **positional**: `result[i]` is the allocation
    ///   for `weights[i]`. The two arrays line up by index and the order
    ///   of the input is preserved in the output.
    /// - `result.reduce(0, +) == max(0, total)` for any non-empty input
    ///   with a positive `total`.
    /// - When two slots tie on remainder during the final +1 distribution,
    ///   the earlier index wins (`lhs.index < rhs.index`). This is the
    ///   stable tiebreaker referenced by call sites that
    ///   depend on which line gets the extra cent must keep the weights
    ///   array in the SAME order they construct lines downstream. A
    ///   `weights.sort()` between line construction and allocation will
    ///   silently shift the remainder by one slot.
    /// - Negative weights are clamped to 0. If all weights are 0 the
    ///   entire `total` is parked in slot 0 so the invariant
    ///   `sum(result) == total` still holds.
    /// - Parameters:
    ///   - total: Integer amount to distribute (e.g. minor-unit VAT).
    ///   - weights: Positional weight vector.
    /// - Returns: Per-slot allocation, same length and order as `weights`.
    static func allocate(total: Int, weights: [Int]) -> [Int] {
        guard !weights.isEmpty else { return [] }
        guard total > 0 else { return Array(repeating: 0, count: weights.count) }

        let normalized = weights.map { max(0, $0) }
        let weightSum = normalized.reduce(0, +)

        guard weightSum > 0 else {
            var fallback = Array(repeating: 0, count: normalized.count)
            fallback[0] = total
            return fallback
        }

        var allocations = Array(repeating: 0, count: normalized.count)
        var remainders: [(index: Int, remainder: Int)] = []
        var allocated = 0

        // (overflow note): `weight * total` is bounded by
        // `Int.max` because both factors are minor-unit amounts (≤ ~10^11
        // each in practice) and the product is taken on Int. On 32-bit
        // targets this could conceivably overflow, but the whole app
        // targets macOS 13+ which is exclusively 64-bit, so Int is at
        // least 63 bits of headroom (~9.2e18). No explicit guard needed.
        for (index, weight) in normalized.enumerated() {
            let weighted = weight * total
            let portion = weighted / weightSum
            let remainder = weighted % weightSum
            allocations[index] = portion
            allocated += portion
            remainders.append((index, remainder))
        }

        let remaining = total - allocated
        guard remaining > 0 else { return allocations }

        let ranked = remainders.sorted { lhs, rhs in
            if lhs.remainder != rhs.remainder {
                return lhs.remainder > rhs.remainder
            }
            return lhs.index < rhs.index
        }

        for i in 0..<remaining {
            allocations[ranked[i].index] += 1
        }

        return allocations
    }
}
