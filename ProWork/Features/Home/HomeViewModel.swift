//  HomeViewModel.swift
//  ProWork
//  Created by Pronomi.

import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var todos: [TodoListItem] = []
    @Published private(set) var sessions: [WorkSessionListItem] = []
    @Published var errorMessage: String?

    private let todoRepository: TodoRepository
    private let sessionRepository: TodoTimeSessionRepository

    /// Cache for the last 7-day aggregation. The view
    /// previously recomputed buckets on every clock tick (≈60×/min); the
    /// output only changes when sessions reload or the calendar day
    /// rolls over. Invalidate the cache when either dependency changes.
    private var weeklyCache: [HomeWeeklyBucket]?
    private var weeklyCacheDayKey: Date?

    init(services: AppServices = .shared) {
        self.todoRepository = services.todoRepository
        self.sessionRepository = services.todoTimeSessionRepository
    }

    func loadData() {
        do {
            todos = try todoRepository.fetchAll()
            sessions = try sessionRepository.fetchAllListItems()
            errorMessage = nil
            weeklyCache = nil  // sessions changed → invalidate
            todoLookupCache = nil
            monthSessionsCache = nil
            monthSessionsCacheKey = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // TodoListItem id → item lookup is invariant between
    // session-list changes, so the per-body Dictionary build was
    // wasted work on every clock tick.
    private var todoLookupCache: [String: TodoListItem]?
    func todoLookup() -> [String: TodoListItem] {
        if let cached = todoLookupCache { return cached }
        let dict = Dictionary(uniqueKeysWithValues: todos.map { ($0.id, $0) })
        todoLookupCache = dict
        return dict
    }

    // Month-bucket sessions cache. Invalidated when sessions
    // reload OR the calendar-month bracket rolls over (the view
    // passes the current `clockTicker.halfMinute` so a tick that
    // crosses month-end naturally re-evaluates the key).
    private var monthSessionsCache: [WorkSessionListItem]?
    private var monthSessionsCacheKey: Date?
    func currentMonthSessions(reference: Date) -> [WorkSessionListItem] {
        let calendar = AppCalendar.istanbul
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: reference)) ?? reference
        if let cached = monthSessionsCache, monthSessionsCacheKey == monthStart {
            return cached
        }
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? reference
        let filtered = sessions.filter { session in
            session.endedAt != nil &&
            session.startedAt >= monthStart &&
            session.startedAt < nextMonth
        }
        monthSessionsCache = filtered
        monthSessionsCacheKey = monthStart
        return filtered
    }

    func weeklyData(reference: Date) -> [HomeWeeklyBucket] {
        // Bucket the week by Istanbul TZ so a user travelling
        // doesn't see weekly totals shift on every TZ change. The
        // billing pipeline already anchors to Istanbul; the Home
        // widget follows the same discipline.
        let calendar = AppCalendar.istanbul
        let startOfToday = calendar.startOfDay(for: reference)

        if let cached = weeklyCache, weeklyCacheDayKey == startOfToday {
            return cached
        }

        var buckets: [HomeWeeklyBucket] = []
        for offset in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) else { continue }
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let total = sessions
                .filter { $0.endedAt != nil && $0.startedAt >= day && $0.startedAt < nextDay }
                .reduce(0) { $0 + ($1.durationSeconds ?? 0) }
            buckets.append(HomeWeeklyBucket(date: day, seconds: total))
        }
        weeklyCache = buckets
        weeklyCacheDayKey = startOfToday
        return buckets
    }
}

struct HomeWeeklyBucket {
    let date: Date
    let seconds: Int
}
