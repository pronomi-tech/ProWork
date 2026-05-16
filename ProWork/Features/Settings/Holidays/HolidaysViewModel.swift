//
//  HolidaysViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//

import Combine
import Foundation

@MainActor
final class HolidaysViewModel: ObservableObject {
    @Published private(set) var holidays: [Holiday] = []
    @Published var errorMessage: String?

    private let holidayRepository: HolidayRepository

    init(services: AppServices = .shared) {
        self.holidayRepository = services.holidayRepository
    }

    func load() {
        do {
            holidays = try holidayRepository.fetchAll(
                organizationId: BuiltInOrganizationId.default,
                includingInactive: true
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func create(_ holiday: Holiday) -> Bool {
        do {
            try holidayRepository.insert(holiday)
            load()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func update(_ holiday: Holiday) -> Bool {
        do {
            try holidayRepository.update(holiday)
            load()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func softDelete(id: String) {
        do {
            try holidayRepository.softDelete(id: id)
            load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
