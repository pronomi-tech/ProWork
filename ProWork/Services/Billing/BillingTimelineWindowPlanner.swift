//  BillingTimelineWindowPlanner.swift
//  ProWork
//  Created by Pronomi

import Foundation

struct BillingTimelineWindowRequest: Hashable {
    struct GroupKey: Hashable {
        let customerId: String
        let windowMinutes: Int
        let currency: String

        init(customerId: String, windowMinutes: Int, currency: String = "") {
            self.customerId = customerId
            self.windowMinutes = windowMinutes
            self.currency = currency
        }
    }

    let sessionId: String
    let groupKey: GroupKey
    let startedAt: Date
    let endedAt: Date
    let actualSeconds: Int
}

enum BillingTimelineWindowPlanner {
    /// Groups records while their starts remain inside the billing windows
    /// already occupied by the chain. A record longer than one window extends
    /// that coverage to the end of its last full minimum window.
    /// Actual seconds stay on every record; only the chain's final record
    /// receives the seconds needed to round the chain total up to a full window.
    static func plan(
        requests: [BillingTimelineWindowRequest]
    ) -> [String: Int] {
        let grouped = Dictionary(grouping: requests) { $0.groupKey }
        var result: [String: Int] = [:]

        for (groupKey, groupRequests) in grouped {
            let sorted = groupRequests.sorted {
                if $0.startedAt != $1.startedAt {
                    return $0.startedAt < $1.startedAt
                }
                if $0.endedAt != $1.endedAt {
                    return $0.endedAt < $1.endedAt
                }
                return $0.sessionId < $1.sessionId
            }

            var chain: [BillingTimelineWindowRequest] = []
            var chainWindowEnd: Date?

            func flushChain() {
                applyMinimumWindow(to: chain, windowMinutes: groupKey.windowMinutes, result: &result)
                chain.removeAll(keepingCapacity: true)
                chainWindowEnd = nil
            }

            for request in sorted {
                let requestWindowEnd = standaloneWindowEnd(
                    for: request,
                    windowMinutes: groupKey.windowMinutes
                )

                if let activeWindowEnd = chainWindowEnd,
                   request.startedAt < activeWindowEnd {
                    chain.append(request)
                    if requestWindowEnd > activeWindowEnd {
                        chainWindowEnd = requestWindowEnd
                    }
                } else {
                    flushChain()
                    chain = [request]
                    chainWindowEnd = requestWindowEnd
                }
            }

            flushChain()
        }

        return result
    }

    private static func standaloneWindowEnd(
        for request: BillingTimelineWindowRequest,
        windowMinutes: Int
    ) -> Date {
        let occupiedSeconds = MinimumWindowApplier.applySeconds(
            actualSeconds: request.actualSeconds,
            windowMinutes: windowMinutes
        )
        return request.startedAt.addingTimeInterval(TimeInterval(occupiedSeconds))
    }

    /// Treats every record in a statement/currency group as a single duration
    /// total and puts the complete rounding difference on its final record.
    static func planReport(
        requests: [BillingTimelineWindowRequest]
    ) -> [String: Int] {
        let grouped = Dictionary(grouping: requests) { $0.groupKey }
        var result: [String: Int] = [:]

        for (groupKey, groupRequests) in grouped {
            let sorted = sortedRequests(groupRequests)
            applyMinimumWindow(to: sorted, windowMinutes: groupKey.windowMinutes, result: &result)
        }

        return result
    }

    private static func applyMinimumWindow(
        to requests: [BillingTimelineWindowRequest],
        windowMinutes: Int,
        result: inout [String: Int]
    ) {
        guard !requests.isEmpty else { return }

        let actualSeconds = requests.map { max(0, $0.actualSeconds) }
        let actualTotal = actualSeconds.reduce(0, +)
        let roundedTotal = MinimumWindowApplier.applySeconds(
            actualSeconds: actualTotal,
            windowMinutes: windowMinutes
        )

        for (request, seconds) in zip(requests, actualSeconds) {
            result[request.sessionId] = seconds
        }
        if let last = requests.last {
            result[last.sessionId, default: 0] += roundedTotal - actualTotal
        }
    }

    private static func sortedRequests(
        _ requests: [BillingTimelineWindowRequest]
    ) -> [BillingTimelineWindowRequest] {
        requests.sorted {
            if $0.startedAt != $1.startedAt {
                return $0.startedAt < $1.startedAt
            }
            if $0.endedAt != $1.endedAt {
                return $0.endedAt < $1.endedAt
            }
            return $0.sessionId < $1.sessionId
        }
    }
}
