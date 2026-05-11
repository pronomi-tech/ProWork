//
//  DatabaseMigrator.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

protocol Migration {
    var id: Int { get }
    var name: String { get }

    func up(_ database: AppDatabase) throws
}
