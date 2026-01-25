# Oraia Classical

Oraia Classical is a focused Ancient Greek lexicon and morphology companion. Search by lemma, filter by learning status and favorites, and open each entry for grouped senses and detailed forms. Noun declensions and verb conjugations are presented by dialect with a built‑in quiz mode for quick self‑testing.

## Highlights
- Dictionary search by lemma with saved filter settings
- Entry details with favorite and learning status tracking
- Senses grouped by part of speech
- Noun and verb form grids separated by dialect
- Reference and quiz study modes

## Status
Work in progress. The core dictionary, entry detail, and forms grid views are implemented; additional lists and POS support are planned.

## Architecture
Oraia Classical is a lightweight SwiftUI app organized around a small, explicit data layer and feature‑scoped views. A single SQLite database (`ag_db.sqlite`) provides lemmas, senses, forms, and lists; the `SQLiteStore` actor owns the connection and exposes focused query and update methods. The UI is split into Dictionary, Entry Detail, and Forms Grid features, each with a dedicated view model that performs async fetches and transforms database rows into display‑ready models.

State that should persist across sessions (search filters) is stored via `AppStorage`, while user updates (favorites and learning status) are written back to SQLite. The Forms Grid page composes reusable noun and verb subviews and a shared quiz state system, grouped by dialect to mirror linguistic usage. This separation keeps database concerns isolated, allows SwiftUI views to stay declarative, and makes it straightforward to add additional parts of speech or study modes over time.

## UI Overview
The app is structured around three primary experiences:

- **Dictionary**: A focused search surface with a persistent settings panel for search mode and filters. Results appear as concise cards showing the lemma, primary part of speech, and learning status, with quick access to entry details.
- **Entry Detail**: A single‑lemma page with a favorite toggle, learning status control, POS tags, and senses grouped by part of speech. Contextual links route directly to noun and verb form grids when available.
- **Forms Grid**: A study‑focused layout that organizes noun/verb forms by dialect and morphology. Users can switch between reference mode and quiz mode, with progress feedback and reveal/reset controls.
