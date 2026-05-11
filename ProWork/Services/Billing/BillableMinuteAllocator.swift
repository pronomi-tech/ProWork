//
//  BillableMinuteAllocator.swift
//  ProWork
//
//  Created by Pronomi
//

import Foundation

enum BillableMinuteAllocator {
    /// Toplam ücretlendirilecek dakikayı süre ağırlığına göre dağıtır.
    /// Dağıtım toplamı korur ve stable largest-remainder kullanır.
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
