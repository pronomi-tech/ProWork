//  ProWorkClockTicker.swift
//  ProWork
//  Centralized clock tick stream injected via `@EnvironmentObject`.
//  Earlier, each `TodoBoardCardView`, `HomeView` and similar widget published
//  its own `Timer.publish(...)` — a board with 50 todos meant 50 active
//  RunLoop timer sources. Concentrate the ticking here so the entire UI
//  shares two timers regardless of how many cards are on screen

import Combine
import Foundation

@MainActor
final class ProWorkClockTicker: ObservableObject {

    /// 1-second tick. Views with tight resolution like an HH:MM:SS active
    /// elapsed time subscribe to this stream.
    @Published private(set) var second: Date = Date()

    /// 30-second tick. Views that only need minute-grain refreshes (e.g.
    /// due-date / idle indicators) subscribe to this stream.
    @Published private(set) var halfMinute: Date = Date()

    private var cancellables: Set<AnyCancellable> = []

    init() {
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.second = now
            }
            .store(in: &cancellables)

        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.halfMinute = now
            }
            .store(in: &cancellables)
    }
}
