//  HolidaysViewModel.swift
//  ProWork
//  Created by Pronomi.

import Combine
import Foundation

@MainActor
final class HolidaysViewModel: ObservableObject, CRUDListViewModel {
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
        performMutation { try holidayRepository.insert(holiday) }
    }

    @discardableResult
    func update(_ holiday: Holiday) -> Bool {
        performMutation { try holidayRepository.update(holiday) }
    }

    func softDelete(id: String) {
        performMutation { try holidayRepository.softDelete(id: id, by: AppServices.currentUserId) }
    }
}
