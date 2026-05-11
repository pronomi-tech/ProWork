//
//  Untitled.swift
//  ProWork
//
//  Created by Pronomi.
//
import Foundation

struct Migration001InitialSchema: Migration {
    let id = 1
    let name = "initial_schema"

    func up(_ database: AppDatabase) throws {
        try createAppSettingsTable(database)

        try createCustomersTable(database)
        try createProjectsTable(database)
        try createTaskCategoriesTable(database)
        try createTodoStatusesTable(database)
        try createTodosTable(database)
        try createTodoTimeSessionsTable(database)

        try applyBillingAndMultiTenantSchema(database)

        try seedDefaultAppSettings(database)
        try seedDefaultTaskCategories(database)
        try seedDefaultTodoStatuses(database)
    }
    
    private func createAppSettingsTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
        );
        """)
    }

    private func createCustomersTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS customers (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            code TEXT,
            contactPerson TEXT,
            address TEXT,
            isActive INTEGER NOT NULL DEFAULT 1,
            defaultPriceListId TEXT,
            defaultServiceType TEXT NOT NULL DEFAULT 'remote',
            defaultMinBillingMinutes INTEGER NOT NULL DEFAULT 60,
            vatRateId TEXT,
            notes TEXT,
            organizationId TEXT NOT NULL DEFAULT 'default_organization',
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (vatRateId) REFERENCES vat_rates(id) ON DELETE SET NULL
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_customers_organizationId
        ON customers(organizationId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_customers_deletedAt
        ON customers(deletedAt);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_customers_vatRateId
        ON customers(vatRateId);
        """)
    }

    private func createProjectsTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS projects (
            id TEXT PRIMARY KEY NOT NULL,
            customerId TEXT NOT NULL,
            name TEXT NOT NULL,
            code TEXT,
            status TEXT NOT NULL DEFAULT 'active',
            defaultServiceType TEXT,
            defaultMinBillingMinutes INTEGER,
            billingWindowMode TEXT
                CHECK(billingWindowMode IN ('timeline','session')),
            vatRateId TEXT,
            notes TEXT,
            organizationId TEXT NOT NULL DEFAULT 'default_organization',
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (customerId) REFERENCES customers(id),
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (vatRateId) REFERENCES vat_rates(id) ON DELETE SET NULL
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_projects_customerId
        ON projects(customerId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_projects_name
        ON projects(name COLLATE NOCASE);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_projects_organizationId
        ON projects(organizationId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_projects_deletedAt
        ON projects(deletedAt);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_projects_vatRateId
        ON projects(vatRateId);
        """)
    }

    private func createTaskCategoriesTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS task_categories (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            color TEXT,
            isBillableDefault INTEGER NOT NULL DEFAULT 1,
            sortOrder INTEGER NOT NULL DEFAULT 0,
            isSystem INTEGER NOT NULL DEFAULT 0,
            vatRateId TEXT,
            organizationId TEXT NOT NULL DEFAULT 'default_organization',
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (vatRateId) REFERENCES vat_rates(id) ON DELETE SET NULL
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_task_categories_name
        ON task_categories(name COLLATE NOCASE);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_task_categories_organizationId
        ON task_categories(organizationId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_task_categories_deletedAt
        ON task_categories(deletedAt);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_task_categories_vatRateId
        ON task_categories(vatRateId);
        """)
    }

    private func createTodoStatusesTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS todo_statuses (
            id TEXT PRIMARY KEY NOT NULL,
            systemKey TEXT UNIQUE,
            name TEXT NOT NULL,
            color TEXT,
            sortOrder INTEGER NOT NULL DEFAULT 0,
            isSystem INTEGER NOT NULL DEFAULT 0,
            isActive INTEGER NOT NULL DEFAULT 1,
            showInBoard INTEGER NOT NULL DEFAULT 1,
            startsTimer INTEGER NOT NULL DEFAULT 0,
            stopsTimer INTEGER NOT NULL DEFAULT 0,
            marksOpen INTEGER NOT NULL DEFAULT 1,
            marksCompleted INTEGER NOT NULL DEFAULT 0,
            marksCancelled INTEGER NOT NULL DEFAULT 0,
            organizationId TEXT NOT NULL DEFAULT 'default_organization',
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todo_statuses_sortOrder
        ON todo_statuses(sortOrder);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todo_statuses_systemKey
        ON todo_statuses(systemKey);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todo_statuses_organizationId
        ON todo_statuses(organizationId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todo_statuses_deletedAt
        ON todo_statuses(deletedAt);
        """)
    }

    private func createTodosTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS todos (
            id TEXT PRIMARY KEY NOT NULL,
            customerId TEXT,
            projectId TEXT,
            categoryId TEXT NOT NULL,
            statusId TEXT NOT NULL DEFAULT 'status_waiting',
            title TEXT NOT NULL,
            description TEXT,
            priority TEXT NOT NULL DEFAULT 'normal',
            plannedDate TEXT,
            dueDate TEXT,
            estimatedMinutes INTEGER,
            isBillable INTEGER NOT NULL DEFAULT 1,
            organizationId TEXT NOT NULL DEFAULT 'default_organization',
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            completedAt TEXT,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (customerId) REFERENCES customers(id),
            FOREIGN KEY (projectId) REFERENCES projects(id),
            FOREIGN KEY (categoryId) REFERENCES task_categories(id),
            FOREIGN KEY (statusId) REFERENCES todo_statuses(id),
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todos_customerId
        ON todos(customerId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todos_projectId
        ON todos(projectId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todos_categoryId
        ON todos(categoryId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todos_statusId
        ON todos(statusId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todos_dueDate
        ON todos(dueDate);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todos_organizationId
        ON todos(organizationId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todos_deletedAt
        ON todos(deletedAt);
        """)
    }
    
    private func createTodoTimeSessionsTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS todo_time_sessions (
            id TEXT PRIMARY KEY NOT NULL,
            todoId TEXT NOT NULL,
            startedAt TEXT NOT NULL,
            runningSinceAt TEXT,
            pausedAt TEXT,
            endedAt TEXT,
            durationSeconds INTEGER,
            startStatusId TEXT,
            endStatusId TEXT,
            note TEXT,
            isManual INTEGER NOT NULL DEFAULT 0,
            organizationId TEXT NOT NULL DEFAULT 'default_organization',
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (todoId) REFERENCES todos(id) ON DELETE CASCADE,
            FOREIGN KEY (startStatusId) REFERENCES todo_statuses(id),
            FOREIGN KEY (endStatusId) REFERENCES todo_statuses(id),
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todo_time_sessions_todoId
        ON todo_time_sessions(todoId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todo_time_sessions_startedAt
        ON todo_time_sessions(startedAt);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todo_time_sessions_open
        ON todo_time_sessions(todoId, endedAt);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todo_time_sessions_organizationId
        ON todo_time_sessions(organizationId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todo_time_sessions_deletedAt
        ON todo_time_sessions(deletedAt);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_todo_time_sessions_open_state
        ON todo_time_sessions(todoId, endedAt, pausedAt);
        """)
    }
    
    private func seedDefaultAppSettings(_ database: AppDatabase) throws {
        let now = DateFormatter.proWorkSQLite.string(from: Date())

        let settings: [(key: String, value: String)] = [
            ("language", "tr"),
            ("dateFormat", "dd.MM.yyyy"),
            ("timeFormat", "HH:mm"),
            ("dateTimeFormat", "dd.MM.yyyy HH:mm"),
            ("fontSize", "normal")
        ]

        for setting in settings {
            try database.execute("""
            INSERT OR IGNORE INTO app_settings (
                key,
                value,
                createdAt,
                updatedAt
            )
            VALUES (?, ?, ?, ?);
            """) { statement in
                statement.bindText(setting.key, at: 1)
                statement.bindText(setting.value, at: 2)
                statement.bindText(now, at: 3)
                statement.bindText(now, at: 4)
            }
        }
    }

    private func seedDefaultTaskCategories(_ database: AppDatabase) throws {
        let now = DateFormatter.proWorkSQLite.string(from: Date())

        let categories: [
            (
                id: String,
                name: String,
                color: String,
                isBillableDefault: Int,
                sortOrder: Int
            )
        ] = [
            ("development", "Geliştirme", "blue", 1, 10),
            ("support", "Destek", "orange", 1, 20),
            ("meeting", "Toplantı", "purple", 1, 30),
            ("analysis", "Analiz", "cyan", 1, 40),
            ("devops", "DevOps", "red", 1, 50),
            ("documentation", "Dokümantasyon", "gray", 1, 60),
            ("field_service", "Saha Servisi", "green", 1, 70),
            ("administrative", "İdari", "gray", 0, 80),
            ("sales", "Satış", "yellow", 0, 90),
            ("rnd", "Ar-Ge", "indigo", 0, 100),
            ("finance", "Finans", "mint", 0, 110)
        ]

        for category in categories {
            try database.execute("""
            INSERT OR IGNORE INTO task_categories (
                id,
                name,
                color,
                isBillableDefault,
                sortOrder,
                isSystem,
                organizationId,
                createdByUserId,
                updatedByUserId,
                createdAt,
                updatedAt
            )
            VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?);
            """) { statement in
                statement.bindText(category.id, at: 1)
                statement.bindText(category.name, at: 2)
                statement.bindText(category.color, at: 3)
                statement.bindInt(category.isBillableDefault, at: 4)
                statement.bindInt(category.sortOrder, at: 5)
                statement.bindText(BuiltInOrganizationId.default, at: 6)
                statement.bindText(BuiltInUserId.defaultOwner, at: 7)
                statement.bindText(BuiltInUserId.defaultOwner, at: 8)
                statement.bindText(now, at: 9)
                statement.bindText(now, at: 10)
            }
        }
    }

    private func seedDefaultTodoStatuses(_ database: AppDatabase) throws {
        let now = DateFormatter.proWorkSQLite.string(from: Date())

        let statuses: [
            (
                id: String,
                systemKey: String,
                name: String,
                color: String,
                sortOrder: Int,
                startsTimer: Int,
                stopsTimer: Int,
                marksOpen: Int,
                marksCompleted: Int,
                marksCancelled: Int,
                showInBoard: Int
            )
        ] = [
            (
                BuiltInTodoStatusId.waiting,
                "waiting",
                "Beklemede",
                "gray",
                10,
                0,
                1,
                1,
                0,
                0,
                1
            ),
            (
                BuiltInTodoStatusId.inProgress,
                "in_progress",
                "Devam Ediyor",
                "blue",
                20,
                1,
                0,
                1,
                0,
                0,
                1
            ),
            (
                BuiltInTodoStatusId.done,
                "done",
                "Tamamlandı",
                "green",
                30,
                0,
                1,
                0,
                1,
                0,
                1
            ),
            (
                BuiltInTodoStatusId.cancelled,
                "cancelled",
                "İptal",
                "red",
                40,
                0,
                1,
                0,
                0,
                1,
                0
            )
        ]

        for status in statuses {
            try database.execute("""
            INSERT OR IGNORE INTO todo_statuses (
                id,
                systemKey,
                name,
                color,
                sortOrder,
                isSystem,
                isActive,
                showInBoard,
                startsTimer,
                stopsTimer,
                marksOpen,
                marksCompleted,
                marksCancelled,
                organizationId,
                createdByUserId,
                updatedByUserId,
                createdAt,
                updatedAt
            )
            VALUES (?, ?, ?, ?, ?, 1, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """) { statement in
                statement.bindText(status.id, at: 1)
                statement.bindText(status.systemKey, at: 2)
                statement.bindText(status.name, at: 3)
                statement.bindText(status.color, at: 4)
                statement.bindInt(status.sortOrder, at: 5)
                statement.bindInt(status.showInBoard, at: 6)
                statement.bindInt(status.startsTimer, at: 7)
                statement.bindInt(status.stopsTimer, at: 8)
                statement.bindInt(status.marksOpen, at: 9)
                statement.bindInt(status.marksCompleted, at: 10)
                statement.bindInt(status.marksCancelled, at: 11)
                statement.bindText(BuiltInOrganizationId.default, at: 12)
                statement.bindText(BuiltInUserId.defaultOwner, at: 13)
                statement.bindText(BuiltInUserId.defaultOwner, at: 14)
                statement.bindText(now, at: 15)
                statement.bindText(now, at: 16)
            }
        }
    }
}

// MARK: - Billing And Multi-Tenant Schema

private extension Migration001InitialSchema {
    func applyBillingAndMultiTenantSchema(_ database: AppDatabase) throws {
        try database.execute("BEGIN TRANSACTION;")

        do {
            try createUsersTable(database)
            try createOrganizationsTable(database)

            try seedDefaultOwnerAndOrganization(database)

            try createCompanyProfileTable(database)
            try createBillingRulesTable(database)
            try createHolidaysTable(database)
            try createExchangeRatesTable(database)
            try createVatRatesTable(database)

            try createPriceListsTable(database)
            try createPriceListRowsTable(database)
            try createTodoBillingOverridesTable(database)

            try createBillingReportRunsTable(database)
            try createBillingReportLinesTable(database)
            try createPaymentsTable(database)

            try seedDefaultCompanyProfile(database)
            try seedDefaultBillingRule(database)
            try seedDefaultVatRates(database)
            try seedTurkishHolidays(database)

            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    func createUsersTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY NOT NULL,
            email TEXT UNIQUE,
            fullName TEXT NOT NULL,
            avatarColor TEXT,
            isActive INTEGER NOT NULL DEFAULT 1,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_users_email
        ON users(email);
        """)
    }

    func createOrganizationsTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS organizations (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            slug TEXT UNIQUE,
            masterCurrency TEXT NOT NULL DEFAULT 'TRY',
            billingWindowMode TEXT NOT NULL DEFAULT 'timeline'
                CHECK(billingWindowMode IN ('timeline','session')),
            isActive INTEGER NOT NULL DEFAULT 1,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT
        );
        """)
    }

    func seedDefaultOwnerAndOrganization(_ database: AppDatabase) throws {
        let now = DateFormatter.proWorkSQLite.string(from: Date())

        try database.execute("""
        INSERT OR IGNORE INTO users (
            id, email, fullName, avatarColor, isActive,
            createdAt, updatedAt, rowVersion, syncStatus
        )
        VALUES (?, NULL, ?, ?, 1, ?, ?, 0, 'local');
        """) { statement in
            statement.bindText(BuiltInUserId.defaultOwner, at: 1)
            statement.bindText("Sahip", at: 2)
            statement.bindText("blue", at: 3)
            statement.bindText(now, at: 4)
            statement.bindText(now, at: 5)
        }

        try database.execute("""
        INSERT OR IGNORE INTO organizations (
            id, name, slug, masterCurrency, billingWindowMode, isActive,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, rowVersion, syncStatus
        )
        VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?, 0, 'local');
        """) { statement in
            statement.bindText(BuiltInOrganizationId.default, at: 1)
            statement.bindText("Varsayılan Organizasyon", at: 2)
            statement.bindText("default", at: 3)
            statement.bindText("TRY", at: 4)
            statement.bindText(BillingWindowMode.timeline.rawValue, at: 5)
            statement.bindText(BuiltInUserId.defaultOwner, at: 6)
            statement.bindText(BuiltInUserId.defaultOwner, at: 7)
            statement.bindText(now, at: 8)
            statement.bindText(now, at: 9)
        }
    }

    func createCompanyProfileTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS company_profile (
            id TEXT PRIMARY KEY NOT NULL,
            organizationId TEXT NOT NULL UNIQUE,
            legalName TEXT NOT NULL,
            tradeName TEXT,
            taxNumber TEXT,
            taxOffice TEXT,
            address TEXT,
            phone TEXT,
            email TEXT,
            website TEXT,
            logoData BLOB,
            paymentTermsDays INTEGER NOT NULL DEFAULT 30,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE
        );
        """)
    }

    func createBillingRulesTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS billing_rules (
            id TEXT PRIMARY KEY NOT NULL,
            organizationId TEXT NOT NULL,
            scope TEXT NOT NULL CHECK(scope IN ('global','customer')),
            customerId TEXT,
            weekdayHours TEXT NOT NULL,
            weekendDays TEXT NOT NULL,
            timezone TEXT NOT NULL DEFAULT 'Europe/Istanbul',
            isActive INTEGER NOT NULL DEFAULT 1,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            UNIQUE(organizationId, scope, customerId),
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_billing_rules_lookup
        ON billing_rules(organizationId, customerId);
        """)
    }

    func createHolidaysTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS holidays (
            id TEXT PRIMARY KEY NOT NULL,
            organizationId TEXT NOT NULL,
            scope TEXT NOT NULL CHECK(scope IN ('global','customer')),
            customerId TEXT,
            date TEXT NOT NULL,
            name TEXT NOT NULL,
            isHalfDay INTEGER NOT NULL DEFAULT 0,
            halfDayCutoff TEXT,
            isActive INTEGER NOT NULL DEFAULT 1,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_holidays_lookup
        ON holidays(organizationId, date);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_holidays_customer
        ON holidays(customerId, date);
        """)
    }

    func createExchangeRatesTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS exchange_rates (
            id TEXT PRIMARY KEY NOT NULL,
            organizationId TEXT NOT NULL,
            fromCurrency TEXT NOT NULL,
            toCurrency TEXT NOT NULL,
            rate TEXT NOT NULL,
            forexBuying TEXT,
            forexSelling TEXT,
            banknoteBuying TEXT,
            banknoteSelling TEXT,
            rateDate TEXT NOT NULL,
            source TEXT NOT NULL CHECK(source IN ('tcmb','global','manual')),
            fetchedAt TEXT NOT NULL,
            note TEXT,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            UNIQUE(organizationId, fromCurrency, toCurrency, rateDate, source),
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_exchange_rates_lookup
        ON exchange_rates(organizationId, fromCurrency, toCurrency, rateDate);
        """)
    }

    func createVatRatesTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS vat_rates (
            id TEXT PRIMARY KEY NOT NULL,
            organizationId TEXT NOT NULL,
            name TEXT NOT NULL,
            rate TEXT NOT NULL DEFAULT '0',
            isDefault INTEGER NOT NULL DEFAULT 0,
            isExempt INTEGER NOT NULL DEFAULT 0,
            isActive INTEGER NOT NULL DEFAULT 1,
            note TEXT,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_vat_rates_org
        ON vat_rates(organizationId, deletedAt);
        """)

        try database.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_vat_rates_default
        ON vat_rates(organizationId)
        WHERE isDefault = 1 AND deletedAt IS NULL;
        """)
    }

    func createPriceListsTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS price_lists (
            id TEXT PRIMARY KEY NOT NULL,
            organizationId TEXT NOT NULL,
            ownerType TEXT NOT NULL
                CHECK(ownerType IN ('global','customer','project')),
            ownerId TEXT,
            name TEXT NOT NULL,
            currency TEXT NOT NULL,
            isActive INTEGER NOT NULL DEFAULT 1,
            isDefault INTEGER NOT NULL DEFAULT 0,
            validFrom TEXT,
            validTo TEXT,
            notes TEXT,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_price_lists_owner
        ON price_lists(organizationId, ownerType, ownerId);
        """)

        try database.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_price_lists_default
        ON price_lists(organizationId, ownerType, COALESCE(ownerId, ''))
        WHERE isDefault = 1 AND deletedAt IS NULL;
        """)
    }

    func createPriceListRowsTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS price_list_rows (
            id TEXT PRIMARY KEY NOT NULL,
            organizationId TEXT NOT NULL,
            priceListId TEXT NOT NULL,
            serviceType TEXT NOT NULL
                CHECK(serviceType IN ('remote','onsite')),
            timeType TEXT NOT NULL
                CHECK(timeType IN ('regular','afterHours','weekend','holiday')),
            categoryId TEXT,
            weekdayMask INTEGER,
            startTime TEXT,
            endTime TEXT,
            unitPriceMinor INTEGER NOT NULL,
            currency TEXT NOT NULL,
            minimumWindowMinutes INTEGER,
            validFrom TEXT,
            validTo TEXT,
            isActive INTEGER NOT NULL DEFAULT 1,
            sortOrder INTEGER NOT NULL DEFAULT 0,
            notes TEXT,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (priceListId) REFERENCES price_lists(id) ON DELETE CASCADE,
            FOREIGN KEY (categoryId) REFERENCES task_categories(id) ON DELETE SET NULL
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_price_list_rows_pl
        ON price_list_rows(priceListId, isActive);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_price_list_rows_match
        ON price_list_rows(priceListId, serviceType, timeType, categoryId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_price_list_rows_organizationId
        ON price_list_rows(organizationId);
        """)
    }

    func createTodoBillingOverridesTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS todo_billing_overrides (
            id TEXT PRIMARY KEY NOT NULL,
            organizationId TEXT NOT NULL,
            todoId TEXT NOT NULL UNIQUE,
            overrideType TEXT NOT NULL
                CHECK(overrideType IN ('unitPrice','fixedFee')),
            unitPriceMinor INTEGER,
            fixedFeeMinor INTEGER,
            currency TEXT NOT NULL,
            note TEXT,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            CHECK (
                (overrideType = 'unitPrice' AND unitPriceMinor IS NOT NULL AND fixedFeeMinor IS NULL)
             OR (overrideType = 'fixedFee'  AND fixedFeeMinor  IS NOT NULL AND unitPriceMinor IS NULL)
            ),
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (todoId) REFERENCES todos(id) ON DELETE CASCADE
        );
        """)
    }

    func createBillingReportRunsTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS billing_report_runs (
            id TEXT PRIMARY KEY NOT NULL,
            organizationId TEXT NOT NULL,
            customerId TEXT NOT NULL,
            periodStart TEXT NOT NULL,
            periodEnd TEXT NOT NULL,
            status TEXT NOT NULL
                CHECK(status IN ('draft','final','cancelled')),
            title TEXT,
            invoiceNumber TEXT,
            currency TEXT NOT NULL,
            subtotalMinor INTEGER NOT NULL DEFAULT 0,
            vatMinor INTEGER NOT NULL DEFAULT 0,
            totalMinor INTEGER NOT NULL DEFAULT 0,
            paidMinor INTEGER NOT NULL DEFAULT 0,
            balanceMinor INTEGER NOT NULL DEFAULT 0,
            paymentStatus TEXT NOT NULL DEFAULT 'unpaid'
                CHECK(paymentStatus IN ('unpaid','partial','paid','overdue')),
            dueDate TEXT,
            snapshotJson TEXT,
            notes TEXT,
            finalizedAt TEXT,
            finalizedByUserId TEXT,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE RESTRICT
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_billing_runs_customer
        ON billing_report_runs(organizationId, customerId, periodStart);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_billing_runs_status
        ON billing_report_runs(organizationId, status, paymentStatus);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_billing_runs_dueDate
        ON billing_report_runs(dueDate);
        """)
    }

    func createBillingReportLinesTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS billing_report_lines (
            id TEXT PRIMARY KEY NOT NULL,
            organizationId TEXT NOT NULL,
            runId TEXT NOT NULL,
            sessionId TEXT,
            todoId TEXT NOT NULL,
            todoTitle TEXT NOT NULL,
            projectId TEXT,
            projectName TEXT,
            customerId TEXT NOT NULL,
            customerName TEXT NOT NULL,
            categoryId TEXT,
            categoryName TEXT,
            serviceType TEXT NOT NULL,
            timeType TEXT NOT NULL,
            segmentIndex INTEGER NOT NULL DEFAULT 0,
            actualSeconds INTEGER NOT NULL DEFAULT 0,
            billableMinutes INTEGER NOT NULL DEFAULT 0,
            unitPriceMinor INTEGER NOT NULL DEFAULT 0,
            fixedFeeMinor INTEGER,
            amountMinor INTEGER NOT NULL DEFAULT 0,
            currency TEXT NOT NULL,
            vatRate TEXT NOT NULL DEFAULT '0',
            vatMinor INTEGER NOT NULL DEFAULT 0,
            totalMinor INTEGER NOT NULL DEFAULT 0,
            isVatExempt INTEGER NOT NULL DEFAULT 0,
            isBillable INTEGER NOT NULL DEFAULT 1,
            isManual INTEGER NOT NULL DEFAULT 0,
            isFixedFee INTEGER NOT NULL DEFAULT 0,
            startedAt TEXT,
            endedAt TEXT,
            note TEXT,
            sortOrder INTEGER NOT NULL DEFAULT 0,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (runId) REFERENCES billing_report_runs(id) ON DELETE CASCADE
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_billing_lines_run
        ON billing_report_lines(runId, sortOrder);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_billing_lines_session
        ON billing_report_lines(sessionId);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_billing_lines_todo
        ON billing_report_lines(todoId);
        """)
    }

    func createPaymentsTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS payments (
            id TEXT PRIMARY KEY NOT NULL,
            organizationId TEXT NOT NULL,
            runId TEXT NOT NULL,
            paidAt TEXT NOT NULL,
            amountMinor INTEGER NOT NULL,
            currency TEXT NOT NULL,
            method TEXT NOT NULL
                CHECK(method IN ('bank_transfer','cash','card','check','other')),
            reference TEXT,
            note TEXT,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (runId) REFERENCES billing_report_runs(id) ON DELETE CASCADE
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_payments_run
        ON payments(runId, paidAt);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_payments_org_paidAt
        ON payments(organizationId, paidAt);
        """)
    }

    func seedDefaultCompanyProfile(_ database: AppDatabase) throws {
        let now = DateFormatter.proWorkSQLite.string(from: Date())

        try database.execute("""
        INSERT OR IGNORE INTO company_profile (
            id, organizationId, legalName, paymentTermsDays,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, rowVersion, syncStatus
        )
        VALUES (?, ?, ?, 30, ?, ?, ?, ?, 0, 'local');
        """) { statement in
            statement.bindText("company_profile_default", at: 1)
            statement.bindText(BuiltInOrganizationId.default, at: 2)
            statement.bindText("Şirketinizin Adı", at: 3)
            statement.bindText(BuiltInUserId.defaultOwner, at: 4)
            statement.bindText(BuiltInUserId.defaultOwner, at: 5)
            statement.bindText(now, at: 6)
            statement.bindText(now, at: 7)
        }
    }

    func seedDefaultBillingRule(_ database: AppDatabase) throws {
        let now = DateFormatter.proWorkSQLite.string(from: Date())

        let weekdayHours = """
        {"1":{"start":"09:00","end":"18:00"},"2":{"start":"09:00","end":"18:00"},"3":{"start":"09:00","end":"18:00"},"4":{"start":"09:00","end":"18:00"},"5":{"start":"09:00","end":"18:00"}}
        """
        let weekendDays = "[6,7]"

        try database.execute("""
        INSERT OR IGNORE INTO billing_rules (
            id, organizationId, scope, customerId,
            weekdayHours, weekendDays, timezone, isActive,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, rowVersion, syncStatus
        )
        VALUES (?, ?, 'global', NULL, ?, ?, 'Europe/Istanbul', 1, ?, ?, ?, ?, 0, 'local');
        """) { statement in
            statement.bindText("billing_rule_default", at: 1)
            statement.bindText(BuiltInOrganizationId.default, at: 2)
            statement.bindText(weekdayHours, at: 3)
            statement.bindText(weekendDays, at: 4)
            statement.bindText(BuiltInUserId.defaultOwner, at: 5)
            statement.bindText(BuiltInUserId.defaultOwner, at: 6)
            statement.bindText(now, at: 7)
            statement.bindText(now, at: 8)
        }
    }

    func seedDefaultVatRates(_ database: AppDatabase) throws {
        let now = DateFormatter.proWorkSQLite.string(from: Date())

        try database.execute("""
        INSERT OR IGNORE INTO vat_rates (
            id, organizationId, name, rate, isDefault, isExempt, isActive,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, rowVersion, syncStatus
        )
        VALUES (?, ?, ?, '0.20', 1, 0, 1, ?, ?, ?, ?, 0, 'local');
        """) { statement in
            statement.bindText(BuiltInVatRateId.defaultStandard, at: 1)
            statement.bindText(BuiltInOrganizationId.default, at: 2)
            statement.bindText("Standart", at: 3)
            statement.bindText(BuiltInUserId.defaultOwner, at: 4)
            statement.bindText(BuiltInUserId.defaultOwner, at: 5)
            statement.bindText(now, at: 6)
            statement.bindText(now, at: 7)
        }

        try database.execute("""
        INSERT OR IGNORE INTO vat_rates (
            id, organizationId, name, rate, isDefault, isExempt, isActive,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, rowVersion, syncStatus
        )
        VALUES (?, ?, ?, '0', 0, 1, 1, ?, ?, ?, ?, 0, 'local');
        """) { statement in
            statement.bindText(BuiltInVatRateId.exempt, at: 1)
            statement.bindText(BuiltInOrganizationId.default, at: 2)
            statement.bindText("Muafiyet", at: 3)
            statement.bindText(BuiltInUserId.defaultOwner, at: 4)
            statement.bindText(BuiltInUserId.defaultOwner, at: 5)
            statement.bindText(now, at: 6)
            statement.bindText(now, at: 7)
        }
    }

    static let turkishHolidaySeed: [(String, String, Bool, String?)] = [
        ("2025-01-01", "Yılbaşı", false, nil),
        ("2025-03-29", "Ramazan Bayramı Arifesi", true, "13:00"),
        ("2025-03-30", "Ramazan Bayramı 1. Günü", false, nil),
        ("2025-03-31", "Ramazan Bayramı 2. Günü", false, nil),
        ("2025-04-01", "Ramazan Bayramı 3. Günü", false, nil),
        ("2025-04-23", "Ulusal Egemenlik ve Çocuk Bayramı", false, nil),
        ("2025-05-01", "Emek ve Dayanışma Günü", false, nil),
        ("2025-05-19", "Atatürk'ü Anma, Gençlik ve Spor Bayramı", false, nil),
        ("2025-06-05", "Kurban Bayramı Arifesi", true, "13:00"),
        ("2025-06-06", "Kurban Bayramı 1. Günü", false, nil),
        ("2025-06-07", "Kurban Bayramı 2. Günü", false, nil),
        ("2025-06-08", "Kurban Bayramı 3. Günü", false, nil),
        ("2025-06-09", "Kurban Bayramı 4. Günü", false, nil),
        ("2025-07-15", "Demokrasi ve Milli Birlik Günü", false, nil),
        ("2025-08-30", "Zafer Bayramı", false, nil),
        ("2025-10-28", "Cumhuriyet Bayramı Arifesi", true, "13:00"),
        ("2025-10-29", "Cumhuriyet Bayramı", false, nil),
        ("2026-01-01", "Yılbaşı", false, nil),
        ("2026-03-19", "Ramazan Bayramı Arifesi", true, "13:00"),
        ("2026-03-20", "Ramazan Bayramı 1. Günü", false, nil),
        ("2026-03-21", "Ramazan Bayramı 2. Günü", false, nil),
        ("2026-03-22", "Ramazan Bayramı 3. Günü", false, nil),
        ("2026-04-23", "Ulusal Egemenlik ve Çocuk Bayramı", false, nil),
        ("2026-05-01", "Emek ve Dayanışma Günü", false, nil),
        ("2026-05-19", "Atatürk'ü Anma, Gençlik ve Spor Bayramı", false, nil),
        ("2026-05-26", "Kurban Bayramı Arifesi", true, "13:00"),
        ("2026-05-27", "Kurban Bayramı 1. Günü", false, nil),
        ("2026-05-28", "Kurban Bayramı 2. Günü", false, nil),
        ("2026-05-29", "Kurban Bayramı 3. Günü", false, nil),
        ("2026-05-30", "Kurban Bayramı 4. Günü", false, nil),
        ("2026-07-15", "Demokrasi ve Milli Birlik Günü", false, nil),
        ("2026-08-30", "Zafer Bayramı", false, nil),
        ("2026-10-28", "Cumhuriyet Bayramı Arifesi", true, "13:00"),
        ("2026-10-29", "Cumhuriyet Bayramı", false, nil),
        ("2027-01-01", "Yılbaşı", false, nil),
        ("2027-03-09", "Ramazan Bayramı Arifesi", true, "13:00"),
        ("2027-03-10", "Ramazan Bayramı 1. Günü", false, nil),
        ("2027-03-11", "Ramazan Bayramı 2. Günü", false, nil),
        ("2027-03-12", "Ramazan Bayramı 3. Günü", false, nil),
        ("2027-04-23", "Ulusal Egemenlik ve Çocuk Bayramı", false, nil),
        ("2027-05-01", "Emek ve Dayanışma Günü", false, nil),
        ("2027-05-16", "Kurban Bayramı Arifesi", true, "13:00"),
        ("2027-05-17", "Kurban Bayramı 1. Günü", false, nil),
        ("2027-05-18", "Kurban Bayramı 2. Günü", false, nil),
        ("2027-05-19", "Atatürk'ü Anma, Gençlik ve Spor Bayramı", false, nil),
        ("2027-05-19", "Kurban Bayramı 3. Günü", false, nil),
        ("2027-05-20", "Kurban Bayramı 4. Günü", false, nil),
        ("2027-07-15", "Demokrasi ve Milli Birlik Günü", false, nil),
        ("2027-08-30", "Zafer Bayramı", false, nil),
        ("2027-10-28", "Cumhuriyet Bayramı Arifesi", true, "13:00"),
        ("2027-10-29", "Cumhuriyet Bayramı", false, nil),
        ("2028-01-01", "Yılbaşı", false, nil),
        ("2028-02-26", "Ramazan Bayramı Arifesi", true, "13:00"),
        ("2028-02-27", "Ramazan Bayramı 1. Günü", false, nil),
        ("2028-02-28", "Ramazan Bayramı 2. Günü", false, nil),
        ("2028-02-29", "Ramazan Bayramı 3. Günü", false, nil),
        ("2028-04-23", "Ulusal Egemenlik ve Çocuk Bayramı", false, nil),
        ("2028-05-01", "Emek ve Dayanışma Günü", false, nil),
        ("2028-05-05", "Kurban Bayramı Arifesi", true, "13:00"),
        ("2028-05-06", "Kurban Bayramı 1. Günü", false, nil),
        ("2028-05-07", "Kurban Bayramı 2. Günü", false, nil),
        ("2028-05-08", "Kurban Bayramı 3. Günü", false, nil),
        ("2028-05-09", "Kurban Bayramı 4. Günü", false, nil),
        ("2028-05-19", "Atatürk'ü Anma, Gençlik ve Spor Bayramı", false, nil),
        ("2028-07-15", "Demokrasi ve Milli Birlik Günü", false, nil),
        ("2028-08-30", "Zafer Bayramı", false, nil),
        ("2028-10-28", "Cumhuriyet Bayramı Arifesi", true, "13:00"),
        ("2028-10-29", "Cumhuriyet Bayramı", false, nil),
        ("2029-01-01", "Yılbaşı", false, nil),
        ("2029-02-14", "Ramazan Bayramı Arifesi", true, "13:00"),
        ("2029-02-15", "Ramazan Bayramı 1. Günü", false, nil),
        ("2029-02-16", "Ramazan Bayramı 2. Günü", false, nil),
        ("2029-02-17", "Ramazan Bayramı 3. Günü", false, nil),
        ("2029-04-23", "Ulusal Egemenlik ve Çocuk Bayramı", false, nil),
        ("2029-04-25", "Kurban Bayramı Arifesi", true, "13:00"),
        ("2029-04-26", "Kurban Bayramı 1. Günü", false, nil),
        ("2029-04-27", "Kurban Bayramı 2. Günü", false, nil),
        ("2029-04-28", "Kurban Bayramı 3. Günü", false, nil),
        ("2029-04-29", "Kurban Bayramı 4. Günü", false, nil),
        ("2029-05-01", "Emek ve Dayanışma Günü", false, nil),
        ("2029-05-19", "Atatürk'ü Anma, Gençlik ve Spor Bayramı", false, nil),
        ("2029-07-15", "Demokrasi ve Milli Birlik Günü", false, nil),
        ("2029-08-30", "Zafer Bayramı", false, nil),
        ("2029-10-28", "Cumhuriyet Bayramı Arifesi", true, "13:00"),
        ("2029-10-29", "Cumhuriyet Bayramı", false, nil),
        ("2030-01-01", "Yılbaşı", false, nil),
        ("2030-02-04", "Ramazan Bayramı Arifesi", true, "13:00"),
        ("2030-02-05", "Ramazan Bayramı 1. Günü", false, nil),
        ("2030-02-06", "Ramazan Bayramı 2. Günü", false, nil),
        ("2030-02-07", "Ramazan Bayramı 3. Günü", false, nil),
        ("2030-04-13", "Kurban Bayramı Arifesi", true, "13:00"),
        ("2030-04-14", "Kurban Bayramı 1. Günü", false, nil),
        ("2030-04-15", "Kurban Bayramı 2. Günü", false, nil),
        ("2030-04-16", "Kurban Bayramı 3. Günü", false, nil),
        ("2030-04-17", "Kurban Bayramı 4. Günü", false, nil),
        ("2030-04-23", "Ulusal Egemenlik ve Çocuk Bayramı", false, nil),
        ("2030-05-01", "Emek ve Dayanışma Günü", false, nil),
        ("2030-05-19", "Atatürk'ü Anma, Gençlik ve Spor Bayramı", false, nil),
        ("2030-07-15", "Demokrasi ve Milli Birlik Günü", false, nil),
        ("2030-08-30", "Zafer Bayramı", false, nil),
        ("2030-10-28", "Cumhuriyet Bayramı Arifesi", true, "13:00"),
        ("2030-10-29", "Cumhuriyet Bayramı", false, nil)
    ]

    func seedTurkishHolidays(_ database: AppDatabase) throws {
        let now = DateFormatter.proWorkSQLite.string(from: Date())

        for (date, name, isHalfDay, cutoff) in Self.turkishHolidaySeed {
            let id = "holiday_tr_\(date)_\(stableSlug(name))"

            try database.execute("""
            INSERT OR IGNORE INTO holidays (
                id, organizationId, scope, customerId,
                date, name, isHalfDay, halfDayCutoff, isActive,
                createdByUserId, updatedByUserId,
                createdAt, updatedAt, rowVersion, syncStatus
            )
            VALUES (?, ?, 'global', NULL, ?, ?, ?, ?, 1, ?, ?, ?, ?, 0, 'local');
            """) { statement in
                statement.bindText(id, at: 1)
                statement.bindText(BuiltInOrganizationId.default, at: 2)
                statement.bindText(date, at: 3)
                statement.bindText(name, at: 4)
                statement.bindInt(isHalfDay ? 1 : 0, at: 5)
                statement.bindText(cutoff, at: 6)
                statement.bindText(BuiltInUserId.defaultOwner, at: 7)
                statement.bindText(BuiltInUserId.defaultOwner, at: 8)
                statement.bindText(now, at: 9)
                statement.bindText(now, at: 10)
            }
        }
    }

    func stableSlug(_ value: String) -> String {
        let lower = value.lowercased(with: Locale(identifier: "tr_TR"))
        let map: [Character: Character] = [
            "ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u"
        ]
        var result = ""
        for ch in lower {
            if let m = map[ch] {
                result.append(m)
            } else if ch.isLetter || ch.isNumber {
                result.append(ch)
            } else {
                result.append("_")
            }
        }
        while result.contains("__") {
            result = result.replacingOccurrences(of: "__", with: "_")
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

}
