# Changelog

All notable changes to ProWork will be documented in this file.

This project follows a practical versioning style based on public releases.

---

## [Unreleased]

### Added

- Planned customer-based price list module.
- Planned billing calculation engine.
- Planned customer, project and todo based reports.
- Planned CSV export.
- Planned PDF export.
- Planned backup and restore tools.
- Planned work calendar settings.
- Planned billing settings.
- Planned advanced work session filters.

### Changed

- Ongoing UI standardization across forms and screens.
- Ongoing replacement of native SwiftUI inputs with shared ProWork components.
- Ongoing form scaling improvements for different font size settings.

### Technical Direction

- Shared formatting should use `ProWorkFormatters`.
- Shared colors should use `ProWorkColors`.
- Shared labels should use `ProWorkLabels`.
- Date and time formatting should use `AppSettingsStore`.
- Font scaling should use `ProWorkFonts` and `ProWorkTextStyle`.
- General layout scaling should use `ProWorkLayout.scaled`.
- Form-specific proportional scaling should use `ProWorkLayout.formScaled`.

---

## [0.1.0] - Initial Public Preview

### Release Notice

- This release is distributed **without Apple code signing and without notarization**. macOS may show a Gatekeeper warning on first launch; see the README installation notes for the expected workaround.

### Added

- Native macOS application foundation.
- Customer management.
- Project management.
- Todo management.
- Todo board / kanban-style workflow.
- Task categories.
- Workflow statuses.
- Work session tracking.
- Manual work entry.
- Manual work records marked with source information.
- Active work session tracking.
- Start/stop actions on todo cards.
- Protection against editing active work sessions.
- Central work sessions list.
- Todo-specific work sessions view.
- General settings screen.
- Date format setting.
- Time format setting.
- Date/time format setting.
- Font size setting.
- Shared form shell and form header.
- Shared searchable picker component.
- Shared button label component.
- Shared text field component.
- Shared text editor component.
- Shared date/time field direction.
- Shared calendar picker direction.
- Initial UI scaling support.

### Improved

- Todo card action menu changed from native menu to custom popover style.
- Work session form consolidated for manual create/edit scenarios.
- Manual work entry now requires a todo selection before saving.
- Work session tables prepared for wide layouts with horizontal scrolling.
- Sidebar text and layout adjusted for font size settings.
- Settings screen connected to real general settings.
- Date/time display centralized through settings.

### Known Limitations

- Advanced reporting is not complete yet.
- Billing engine is not complete yet.
- Customer-specific price lists are not complete yet.
- PDF export is not complete yet.
- CSV export is not complete yet.
- Backup and restore features are not complete yet.
- Some forms may still need migration to shared ProWork UI components.
- Public preview builds are currently unsigned and not notarized.

---

## Versioning Notes

Suggested future release flow:

```text
0.1.x  Public preview and UI stabilization
0.2.x  Reporting filters and basic reports
0.3.x  Customer/project reports
0.4.x  Billing data model and price lists
0.5.x  Billing calculation engine
0.6.x  Export features
1.0.0  Stable public release
```

---

## Release Checklist

Before each public release:

- Run a clean build.
- Verify no secrets are committed.
- Verify no local database files are committed.
- Verify README is up to date.
- Verify CHANGELOG is updated.
- Create a version tag.
- Build macOS app archive.
- Prepare ZIP or DMG.
- If the release is unsigned and not notarized, document the Gatekeeper warning in README and release notes.
- Upload binary to GitHub Releases.
