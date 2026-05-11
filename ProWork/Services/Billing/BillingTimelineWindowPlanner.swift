//
//  BillingTimelineWindowPlanner.swift
//  ProWork
//
//  Created by Pronomi
//

import Foundation

struct BillingTimelineWindowRequest: Hashable {
    struct GroupKey: Hashable {
        let customerId: String
        let windowMinutes: Int
    }

    let sessionId: String
    let groupKey: GroupKey
    let startedAt: Date
    let endedAt: Date
    let actualSeconds: Int
}

enum BillingTimelineWindowPlanner {
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

            var cluster: [BillingTimelineWindowRequest] = []
            var clusterEnd: Date?

            func flushCluster() {
                guard !cluster.isEmpty, let activeEnd = clusterEnd else { return }
                let clusterStart = cluster[0].startedAt
                let totalBillableMinutes = Int(activeEnd.timeIntervalSince(clusterStart) / 60)
                let allocations = BillableMinuteAllocator.allocate(
                    durationSeconds: cluster.map(\.actualSeconds),
                    totalBillableMinutes: totalBillableMinutes
                )

                for (request, allocatedMinutes) in zip(cluster, allocations) {
                    result[request.sessionId] = allocatedMinutes
                }

                cluster.removeAll(keepingCapacity: true)
                clusterEnd = nil
            }

            for request in sorted {
                if cluster.isEmpty {
                    cluster = [request]
                    clusterEnd = request.startedAt.addingTimeInterval(TimeInterval(groupKey.windowMinutes * 60))
                } else if let activeEnd = clusterEnd, request.startedAt < activeEnd {
                    cluster.append(request)
                } else {
                    flushCluster()
                    cluster = [request]
                    clusterEnd = request.startedAt.addingTimeInterval(TimeInterval(groupKey.windowMinutes * 60))
                }

                while let activeEnd = clusterEnd, request.endedAt > activeEnd {
                    clusterEnd = activeEnd.addingTimeInterval(TimeInterval(groupKey.windowMinutes * 60))
                }
            }

            flushCluster()
        }

        return result
    }
}
