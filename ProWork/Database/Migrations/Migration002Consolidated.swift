//  Migration002Consolidated.swift
//  ProWork
//  Created by Pronomi.
//  Consolidated post-initial-schema bundle. Treats every schema change
//  introduced after Migration001 as if it had been authored in a single
//  pass; previous incremental migrations (M002…M007) are folded into
//  this one. Runs inside the orchestrator's atomic transaction, so the
//  whole bundle either applies or does not apply.
//
//  Sections:
//   - `billing_report_runs.documentNumber` column + unique partial index
//     for the `HD-YYYY-NNNNNN` invoice identifier.
//   - `billing_document_sequences` table for atomic per-year invoice
//     number reservation via SQL UPSERT.
//   - Partial unique index on `todo_time_sessions` so at most one open
//     session can exist per organization.
//   - `vat_rates.effectiveFrom` column for back-dated VAT-rate guards.
//   - BEFORE DELETE trigger on `todos` blocking hard-delete when active
//     `billing_report_lines` reference exists.
//   - `idx_billing_runs_unpaid` covering partial index for the
//     `fetchUnpaid` query.
//   - Partial `idx_billing_lines_session` (restricted to non-NULL
//     `sessionId`); supersedes the non-partial index from Migration001.
//   - BEFORE DELETE trigger on `customers` blocking hard-delete when
//     active `projects` / `todos` / `billing_report_runs` reference it.
//   - `billing_report_run_snapshots` append-only history table + BEFORE
//     UPDATE/DELETE triggers enforcing the append-only contract.
//   - Soft-delete cascade triggers across the ownership chain:
//     customers→projects, customers→todos, projects→todos,
//     todos→todo_time_sessions, todos→todo_billing_overrides,
//     todos→draft billing_report_lines.
//   - Trigger-based `ON DELETE SET NULL` for
//     `customers.defaultPriceListId` on `price_lists` hard- and
//     soft-delete (SQLite cannot add a real FK via ALTER).
//   - `company_profile.logoData` ≤ 5 MB enforcement via BEFORE
//     INSERT / UPDATE triggers.
//   - Composite `(organizationId, deletedAt)` indexes on hot
//     tenant-scoped tables.
//   - `billing_document_sequences` seed (nextValue=0) for every active
//     organization for the current year so a freshly migrated DB's
//     first `reserveNext` returns 1 deterministically.
//   - `billing_rules.schemaVersion` (default 1) marker for future JSON
//     shape upgrades.
//   - `task_categories.i18nKey` column + stable keys for the 11
//     system categories seeded by Migration001.
//   - `quote_document_sequences` mirror of the billing-number table,
//     for atomic quote-number reservation.

import Foundation

struct Migration002Consolidated: Migration {
    let id = 2
    let name = "consolidated post-initial schema"

    func up(_ database: AppDatabase) throws {
        try addBillingRunsDocumentNumber(database)
        try addBillingDocumentSequenceTable(database)
        try addSingleOpenSessionIndex(database)
        try addVatRateEffectiveFrom(database)
        try installTodoBillingLineDeleteGuard(database)
        try addBillingRunsUnpaidIndex(database)
        try replaceBillingLinesSessionPartialIndex(database)
        try installCustomerHardDeleteGuard(database)
        try addBillingRunSnapshotHistory(database)
        try enforceAppendOnlyBillingRunSnapshots(database)
        try installSoftDeleteCascadeTriggers(database)
        try installCustomerDefaultPriceListSetNullTriggers(database)
        try installLogoDataSizeLimit(database)
        try addCompositeOrgDeletedAtIndexes(database)
        try seedBillingDocumentSequenceForAllOrganizations(database)
        try addBillingRulesSchemaVersion(database)
        try addTaskCategoryI18nKey(database)
        try addQuoteDocumentSequenceTable(database)
    }

    // MARK: - billing_report_runs.documentNumber

    private func addBillingRunsDocumentNumber(_ database: AppDatabase) throws {
        try database.execute("""
        ALTER TABLE billing_report_runs
        ADD COLUMN documentNumber TEXT;
        """)

        try database.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_billing_runs_document_number
        ON billing_report_runs(organizationId, documentNumber)
        WHERE documentNumber IS NOT NULL;
        """)
    }

    // MARK: - billing_document_sequences

    /// Per-org/per-year invoice-number counter table. The repository
    /// increments via a single SQL UPSERT inside `inWriteTransaction`,
    /// so parallel finalize calls reserve different values atomically.
    private func addBillingDocumentSequenceTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS billing_document_sequences (
            organizationId TEXT NOT NULL,
            year INTEGER NOT NULL,
            nextValue INTEGER NOT NULL,
            updatedAt TEXT NOT NULL,
            PRIMARY KEY (organizationId, year)
        );
        """)
    }

    // MARK: - Single active work session per organization

    /// At most one row with `endedAt IS NULL AND deletedAt IS NULL` per
    /// organization. A "RUNNING" (`pausedAt IS NULL`) and a "PAUSED"
    /// (`pausedAt IS NOT NULL`) session fall into the same bucket. The
    /// service layer already closes existing open sessions on every
    /// startWork; this index is the last line of defence against a bug
    /// or race producing a leftover row.
    private func addSingleOpenSessionIndex(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_todo_time_sessions_one_open
            ON todo_time_sessions (organizationId)
            WHERE endedAt IS NULL AND deletedAt IS NULL;
        """)
    }

    // MARK: - vat_rates.effectiveFrom

    /// Optional `YYYY-MM-DD` effective date so a rate is not snapshotted
    /// for a period that starts before the rate took effect. The
    /// finalize flow emits a log warning when periodStart precedes the
    /// resolved rate's `effectiveFrom`.
    private func addVatRateEffectiveFrom(_ database: AppDatabase) throws {
        try database.execute("ALTER TABLE vat_rates ADD COLUMN effectiveFrom TEXT;")
    }

    // MARK: - Todo hard-delete guard

    /// `billing_report_lines.todoId` cannot carry a real FK because
    /// SQLite doesn't support `ALTER TABLE ADD CONSTRAINT`. A BEFORE
    /// DELETE trigger on `todos` reproduces ON DELETE RESTRICT by
    /// aborting when an active `billing_report_lines` row references it.
    /// The application layer only calls `softDelete`; this guard catches
    /// hard-deletes coming from the SQL console or a future bug.
    private func installTodoBillingLineDeleteGuard(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_todos_block_delete_if_billed
        BEFORE DELETE ON todos
        FOR EACH ROW
        WHEN EXISTS (
            SELECT 1
            FROM billing_report_lines
            WHERE todoId = OLD.id
              AND deletedAt IS NULL
        )
        BEGIN
            SELECT RAISE(ABORT, 'todos.delete blocked: billing_report_lines reference exists; use soft delete instead');
        END;
        """)
    }

    // MARK: - fetchUnpaid covering index

    /// Covers the predicate + ordering used by
    /// `BillingReportRunRepository.fetchUnpaid`:
    ///     WHERE organizationId = ?
    ///       AND status = 'final'
    ///       AND deletedAt IS NULL
    ///       AND paymentStatus IN ('unpaid','partial','overdue')
    ///     ORDER BY dueDate ASC;
    /// Letting both the WHERE and the ORDER BY resolve index-only
    /// removes the in-memory filesort the previous index path used.
    private func addBillingRunsUnpaidIndex(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_billing_runs_unpaid
            ON billing_report_runs (organizationId, dueDate)
            WHERE status = 'final'
              AND deletedAt IS NULL
              AND paymentStatus IN ('unpaid','partial','overdue');
        """)
    }

    // MARK: - Partial billing_report_lines.sessionId index

    /// Replaces Migration001's non-partial `idx_billing_lines_session`
    /// with a partial variant restricted to non-NULL `sessionId`.
    /// `sessionId` is NULL on most rows (manual line, fixed fee, etc.),
    /// so a full index wasted disk. Adding `runId` keeps the
    /// "session references for a run" query index-only as well.
    private func replaceBillingLinesSessionPartialIndex(_ database: AppDatabase) throws {
        try database.execute("DROP INDEX IF EXISTS idx_billing_lines_session;")
        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_billing_lines_session
            ON billing_report_lines (sessionId, runId)
            WHERE sessionId IS NOT NULL;
        """)
    }

    // MARK: - customers hard-delete guard

    /// BEFORE DELETE trigger on `customers` aborting the hard-delete
    /// when an active `projects` / `todos` / `billing_report_runs` row
    /// references it. Mirrors the policy used for `todos` above.
    private func installCustomerHardDeleteGuard(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_customers_block_delete_if_referenced
        BEFORE DELETE ON customers
        FOR EACH ROW
        WHEN EXISTS (
            SELECT 1 FROM projects WHERE customerId = OLD.id AND deletedAt IS NULL
        ) OR EXISTS (
            SELECT 1 FROM todos WHERE customerId = OLD.id AND deletedAt IS NULL
        ) OR EXISTS (
            SELECT 1 FROM billing_report_runs WHERE customerId = OLD.id AND deletedAt IS NULL
        )
        BEGIN
            SELECT RAISE(ABORT, 'customers.delete blocked: active projects, todos, or billing runs reference this customer; use soft delete instead');
        END;
        """)
    }

    // MARK: - Append-only finalized snapshot history

    /// Append-only history table for finalized billing-run snapshots.
    /// Application code is not granted UPDATE or DELETE permission
    /// (enforced by the triggers in `enforceAppendOnlyBillingRunSnapshots`).
    /// The index on `runId + finalizedAt` lets the entire finalize
    /// history of a run be fetched in order.
    private func addBillingRunSnapshotHistory(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS billing_report_run_snapshots (
            id TEXT PRIMARY KEY NOT NULL,
            runId TEXT NOT NULL,
            organizationId TEXT NOT NULL,
            finalizedAt TEXT NOT NULL,
            finalizedByUserId TEXT,
            invoiceNumber TEXT,
            documentNumber TEXT,
            snapshotJson TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            FOREIGN KEY (runId) REFERENCES billing_report_runs(id) ON DELETE RESTRICT
        );
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_billing_run_snapshots_run
            ON billing_report_run_snapshots (runId, finalizedAt);
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_billing_run_snapshots_org_finalized
            ON billing_report_run_snapshots (organizationId, finalizedAt);
        """)
    }

    /// BEFORE UPDATE / DELETE triggers raising `ABORT` so the
    /// append-only contract is enforced at the DB layer, not just by
    /// convention. Finalize still INSERTs new rows freely.
    private func enforceAppendOnlyBillingRunSnapshots(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_billing_run_snapshots_block_update
        BEFORE UPDATE ON billing_report_run_snapshots
        BEGIN
            SELECT RAISE(ABORT, 'billing_report_run_snapshots is append-only; UPDATE is forbidden');
        END;
        """)

        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_billing_run_snapshots_block_delete
        BEFORE DELETE ON billing_report_run_snapshots
        BEGIN
            SELECT RAISE(ABORT, 'billing_report_run_snapshots is append-only; DELETE is forbidden');
        END;
        """)
    }

    // MARK: - Soft-delete cascade

    /// AFTER UPDATE triggers propagating `deletedAt` down the ownership
    /// chain when a parent transitions from "not deleted" → "deleted".
    /// They fire only on that transition so subsequent updates to a
    /// soft-deleted parent don't re-touch children. Each cascaded write
    /// bumps `rowVersion` and forces `syncStatus = 'local'` so the change
    /// surfaces as dirty in the sync pipeline.
    ///
    /// Lines on `final` or `cancelled` runs are intentionally NOT
    /// cascaded — they're historical audit artefacts and must remain
    /// visible so issued invoices reconcile. Only **draft**
    /// `billing_report_lines` follow a soft-deleted todo.
    private func installSoftDeleteCascadeTriggers(_ database: AppDatabase) throws {
        // customers → projects
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_customers_softdelete_cascade_projects
        AFTER UPDATE OF deletedAt ON customers
        WHEN OLD.deletedAt IS NULL AND NEW.deletedAt IS NOT NULL
        BEGIN
            UPDATE projects
            SET deletedAt = NEW.deletedAt,
                updatedAt = NEW.updatedAt,
                updatedByUserId = NEW.updatedByUserId,
                rowVersion = rowVersion + 1,
                syncStatus = 'local'
            WHERE customerId = NEW.id AND deletedAt IS NULL;
        END;
        """)

        // customers → todos
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_customers_softdelete_cascade_todos
        AFTER UPDATE OF deletedAt ON customers
        WHEN OLD.deletedAt IS NULL AND NEW.deletedAt IS NOT NULL
        BEGIN
            UPDATE todos
            SET deletedAt = NEW.deletedAt,
                updatedAt = NEW.updatedAt,
                updatedByUserId = NEW.updatedByUserId,
                rowVersion = rowVersion + 1,
                syncStatus = 'local'
            WHERE customerId = NEW.id AND deletedAt IS NULL;
        END;
        """)

        // projects → todos
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_projects_softdelete_cascade_todos
        AFTER UPDATE OF deletedAt ON projects
        WHEN OLD.deletedAt IS NULL AND NEW.deletedAt IS NOT NULL
        BEGIN
            UPDATE todos
            SET deletedAt = NEW.deletedAt,
                updatedAt = NEW.updatedAt,
                updatedByUserId = NEW.updatedByUserId,
                rowVersion = rowVersion + 1,
                syncStatus = 'local'
            WHERE projectId = NEW.id AND deletedAt IS NULL;
        END;
        """)

        // todos → todo_time_sessions
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_todos_softdelete_cascade_sessions
        AFTER UPDATE OF deletedAt ON todos
        WHEN OLD.deletedAt IS NULL AND NEW.deletedAt IS NOT NULL
        BEGIN
            UPDATE todo_time_sessions
            SET deletedAt = NEW.deletedAt,
                updatedAt = NEW.updatedAt,
                updatedByUserId = NEW.updatedByUserId,
                rowVersion = rowVersion + 1,
                syncStatus = 'local'
            WHERE todoId = NEW.id AND deletedAt IS NULL;
        END;
        """)

        // todos → todo_billing_overrides
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_todos_softdelete_cascade_overrides
        AFTER UPDATE OF deletedAt ON todos
        WHEN OLD.deletedAt IS NULL AND NEW.deletedAt IS NOT NULL
        BEGIN
            UPDATE todo_billing_overrides
            SET deletedAt = NEW.deletedAt,
                updatedAt = NEW.updatedAt,
                updatedByUserId = NEW.updatedByUserId,
                rowVersion = rowVersion + 1,
                syncStatus = 'local'
            WHERE todoId = NEW.id AND deletedAt IS NULL;
        END;
        """)

        // todos → billing_report_lines (drafts only)
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_todos_softdelete_cascade_draft_billing_lines
        AFTER UPDATE OF deletedAt ON todos
        WHEN OLD.deletedAt IS NULL AND NEW.deletedAt IS NOT NULL
        BEGIN
            UPDATE billing_report_lines
            SET deletedAt = NEW.deletedAt,
                updatedAt = NEW.updatedAt,
                updatedByUserId = NEW.updatedByUserId,
                rowVersion = rowVersion + 1,
                syncStatus = 'local'
            WHERE todoId = NEW.id
              AND deletedAt IS NULL
              AND runId IN (
                  SELECT id FROM billing_report_runs
                  WHERE status = 'draft' AND deletedAt IS NULL
              );
        END;
        """)
    }

    // MARK: - customers.defaultPriceListId → price_lists SET NULL

    /// SQLite can't add a real FK to an existing table without
    /// rebuilding it. Triggers reproduce `ON DELETE SET NULL` for both
    /// hard-delete (rare) and soft-delete (the normal path) of a
    /// price list.
    private func installCustomerDefaultPriceListSetNullTriggers(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_price_lists_delete_clear_customer_default
        AFTER DELETE ON price_lists
        BEGIN
            UPDATE customers
            SET defaultPriceListId = NULL,
                updatedAt = OLD.updatedAt,
                rowVersion = rowVersion + 1,
                syncStatus = 'local'
            WHERE defaultPriceListId = OLD.id;
        END;
        """)

        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_price_lists_softdelete_clear_customer_default
        AFTER UPDATE OF deletedAt ON price_lists
        WHEN OLD.deletedAt IS NULL AND NEW.deletedAt IS NOT NULL
        BEGIN
            UPDATE customers
            SET defaultPriceListId = NULL,
                updatedAt = NEW.updatedAt,
                rowVersion = rowVersion + 1,
                syncStatus = 'local'
            WHERE defaultPriceListId = NEW.id;
        END;
        """)
    }

    // MARK: - company_profile.logoData size cap (5 MB)

    /// CHECK constraints can't be added to an existing table without a
    /// full rebuild; BEFORE triggers achieve the same effect by aborting
    /// oversized writes.
    private func installLogoDataSizeLimit(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_company_profile_logo_size_insert
        BEFORE INSERT ON company_profile
        WHEN NEW.logoData IS NOT NULL AND length(NEW.logoData) > 5242880
        BEGIN
            SELECT RAISE(ABORT, 'company_profile.logoData exceeds the 5 MB limit');
        END;
        """)

        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_company_profile_logo_size_update
        BEFORE UPDATE OF logoData ON company_profile
        WHEN NEW.logoData IS NOT NULL AND length(NEW.logoData) > 5242880
        BEGIN
            SELECT RAISE(ABORT, 'company_profile.logoData exceeds the 5 MB limit');
        END;
        """)
    }

    // MARK: - Composite (organizationId, deletedAt) indexes

    /// Tenant-scoped list queries combine `organizationId = ?` with
    /// `deletedAt IS NULL` on every read; a composite index covers
    /// both predicates with one B-tree lookup.
    private func addCompositeOrgDeletedAtIndexes(_ database: AppDatabase) throws {
        for table in ["customers", "projects", "task_categories", "todos"] {
            try database.execute("""
            CREATE INDEX IF NOT EXISTS idx_\(table)_org_deletedAt
            ON \(table)(organizationId, deletedAt);
            """)
        }
    }

    // MARK: - billing_document_sequences seed for every organization

    /// Seeds `nextValue = 0` for the current Gregorian year for every
    /// active organization. `BillingDocumentSequenceRepository.reserveNext`
    /// does `INSERT OR IGNORE (org, year, 0)` then
    /// `UPDATE nextValue = nextValue + 1`, so a fresh row at 0 yields the
    /// canonical first reservation value of 1. Seeding with 1 here would
    /// make the first reservation return 2 (regression caught by the
    /// integration test).
    private func seedBillingDocumentSequenceForAllOrganizations(_ database: AppDatabase) throws {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let now = AppDateFormatters.sqliteTimestamp.string(from: Date())

        try database.execute("""
        INSERT OR IGNORE INTO billing_document_sequences (organizationId, year, nextValue, updatedAt)
        SELECT o.id, ?, 0, ?
        FROM organizations o
        WHERE o.deletedAt IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM billing_document_sequences s
              WHERE s.organizationId = o.id AND s.year = ?
          );
        """) { statement in
            statement.bindInt(currentYear, at: 1)
            statement.bindText(now, at: 2)
            statement.bindInt(currentYear, at: 3)
        }
    }

    // MARK: - billing_rules.schemaVersion marker

    /// Parse-time upgrade marker for the `weekdayHours` / `weekendDays`
    /// JSON shape. Default is 1 (the current shape); future migrations
    /// can bump the value and the loader can branch on it instead of
    /// guessing from the payload.
    private func addBillingRulesSchemaVersion(_ database: AppDatabase) throws {
        try database.execute("""
        ALTER TABLE billing_rules
        ADD COLUMN schemaVersion INTEGER NOT NULL DEFAULT 1;
        """)
    }

    // MARK: - task_categories.i18nKey

    /// Adds a stable localisation key for the 11 system categories
    /// seeded by Migration001 so a future locale switch can translate
    /// them without rewriting every row. Custom user categories keep
    /// `i18nKey = NULL`; repositories fall back to the `name` column
    /// when the key is missing.
    private func addTaskCategoryI18nKey(_ database: AppDatabase) throws {
        try database.execute("ALTER TABLE task_categories ADD COLUMN i18nKey TEXT;")

        let systemKeys: [(id: String, key: String)] = [
            ("development", "taskCategory.development"),
            ("support", "taskCategory.support"),
            ("meeting", "taskCategory.meeting"),
            ("analysis", "taskCategory.analysis"),
            ("devops", "taskCategory.devops"),
            ("documentation", "taskCategory.documentation"),
            ("field_service", "taskCategory.fieldService"),
            ("administrative", "taskCategory.administrative"),
            ("sales", "taskCategory.sales"),
            ("rnd", "taskCategory.rnd"),
            ("finance", "taskCategory.finance"),
        ]

        for entry in systemKeys {
            try database.execute("""
            UPDATE task_categories
            SET i18nKey = ?
            WHERE id = ? AND (i18nKey IS NULL OR i18nKey = '');
            """) { statement in
                statement.bindText(entry.key, at: 1)
                statement.bindText(entry.id, at: 2)
            }
        }
    }

    // MARK: - quote_document_sequences

    /// Mirror of `billing_document_sequences` for quote (Teklif)
    /// numbers. `QuoteDocumentSequenceRepository.reserveNext` does the
    /// atomic UPSERT/INCREMENT/SELECT inside `inWriteTransaction`.
    private func addQuoteDocumentSequenceTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS quote_document_sequences (
            organizationId TEXT NOT NULL,
            year INTEGER NOT NULL,
            nextValue INTEGER NOT NULL,
            updatedAt TEXT NOT NULL,
            PRIMARY KEY (organizationId, year)
        );
        """)
    }
}
