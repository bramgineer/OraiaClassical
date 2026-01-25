import Foundation
import SQLite3

enum SQLiteStoreError: Error, LocalizedError {
    case databaseNotFound
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case readOnly

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "Database resource not found."
        case .openFailed(let message):
            return "Failed to open database: \(message)"
        case .prepareFailed(let message):
            return "Failed to prepare query: \(message)"
        case .stepFailed(let message):
            return "Failed to execute query: \(message)"
        case .readOnly:
            return "Database is read-only. Bundle resources cannot be modified."
        }
    }
}

actor SQLiteStore {
    static let shared = SQLiteStore()

    private var db: OpaquePointer?
    private var posIDByCode: [String: Int64] = [:]
    private(set) var isReadOnly: Bool = false

    init() {
        openDatabase()
        loadPosCodes()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        guard let url = Bundle.main.url(forResource: "ag_db", withExtension: "sqlite") else {
            return
        }

        var connection: OpaquePointer?
        let path = url.path
        let readwrite = sqlite3_open_v2(path, &connection, SQLITE_OPEN_READWRITE, nil)
        if readwrite != SQLITE_OK {
            sqlite3_close(connection)
            connection = nil
            let readonly = sqlite3_open_v2(path, &connection, SQLITE_OPEN_READONLY, nil)
            if readonly != SQLITE_OK {
                sqlite3_close(connection)
                connection = nil
            } else {
                isReadOnly = true
            }
        }

        db = connection
        if let db {
            sqlite3_busy_timeout(db, 2000)
            sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
        }
    }

    private func loadPosCodes() {
        guard let db else { return }
        let sql = "SELECT id, code FROM pos;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            guard let codePointer = sqlite3_column_text(statement, 1) else { continue }
            let code = String(cString: codePointer)
            posIDByCode[code] = id
        }
    }

    private func errorMessage() -> String {
        guard let db, let message = sqlite3_errmsg(db) else { return "Unknown error" }
        return String(cString: message)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let db else { throw SQLiteStoreError.databaseNotFound }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(errorMessage())
        }
        return statement
    }

    private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    func searchLemmas(query: String,
                      mode: SearchMode,
                      favoritesOnly: Bool,
                      learningStatus: LearningStatus?,
                      listTitle: String?,
                      limit: Int = 200) throws -> [LemmaSummary] {
        guard let _ = db else { throw SQLiteStoreError.databaseNotFound }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasFilters = favoritesOnly || learningStatus != nil || (listTitle?.isEmpty == false)
        guard !trimmed.isEmpty || hasFilters else { return [] }

        var sql = """
        SELECT lemma.id, lemma.headword, lemma.is_favorite, lemma.learning_status, pos.code
        FROM lemma
        LEFT JOIN lemma_pos ON lemma.id = lemma_pos.lemma_id AND lemma_pos.is_primary = 1
        LEFT JOIN pos ON lemma_pos.pos_id = pos.id
        WHERE lemma.headword LIKE ?
        """

        if favoritesOnly {
            sql += " AND lemma.is_favorite = 1"
        }

        if learningStatus != nil {
            sql += " AND lemma.learning_status = ?"
        }

        if let listTitle, !listTitle.isEmpty {
            sql += " AND lemma.id IN (SELECT lemma FROM vocabulary_list_entry WHERE vocabulary_list = ?)"
        }

        sql += " ORDER BY lemma.headword LIMIT ?;"

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        let pattern: String
        if trimmed.isEmpty {
            pattern = "%"
        } else {
            switch mode {
            case .startsWith:
                pattern = "\(trimmed)%"
            case .contains:
                pattern = "%\(trimmed)%"
            }
        }

        sqlite3_bind_text(statement, bindIndex, (pattern as NSString).utf8String, -1, nil)
        bindIndex += 1

        if let learningStatus {
            sqlite3_bind_int(statement, bindIndex, Int32(learningStatus.rawValue))
            bindIndex += 1
        }

        if let listTitle, !listTitle.isEmpty {
            sqlite3_bind_text(statement, bindIndex, (listTitle as NSString).utf8String, -1, nil)
            bindIndex += 1
        }

        sqlite3_bind_int(statement, bindIndex, Int32(limit))

        var results: [LemmaSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let headword = stringColumn(statement, index: 1) ?? ""
            let isFavorite = sqlite3_column_int(statement, 2) == 1
            let statusValue = Int(sqlite3_column_int(statement, 3))
            let posCode = stringColumn(statement, index: 4)
            let status = LearningStatus(rawValue: statusValue) ?? .new
            results.append(LemmaSummary(id: id, headword: headword, primaryPOS: posCode, isFavorite: isFavorite, learningStatus: status))
        }

        return results
    }

    func fetchLemmaDetail(id: Int64) throws -> LemmaDetail {
        guard let _ = db else { throw SQLiteStoreError.databaseNotFound }

        let lemmaSql = "SELECT id, headword, notes, is_favorite, learning_status FROM lemma WHERE id = ?;"
        let lemmaStatement = try prepare(lemmaSql)
        defer { sqlite3_finalize(lemmaStatement) }
        sqlite3_bind_int64(lemmaStatement, 1, id)

        guard sqlite3_step(lemmaStatement) == SQLITE_ROW else {
            throw SQLiteStoreError.stepFailed(errorMessage())
        }

        let headword = stringColumn(lemmaStatement, index: 1) ?? ""
        let notes = stringColumn(lemmaStatement, index: 2)
        let isFavorite = sqlite3_column_int(lemmaStatement, 3) == 1
        let statusValue = Int(sqlite3_column_int(lemmaStatement, 4))
        let status = LearningStatus(rawValue: statusValue) ?? .new

        let posCodes = try fetchPosCodes(for: id)
        let senseGroups = try fetchSenseGroups(for: id)

        return LemmaDetail(id: id, headword: headword, notes: notes, isFavorite: isFavorite, learningStatus: status, posCodes: posCodes, senseGroups: senseGroups)
    }

    private func fetchPosCodes(for lemmaID: Int64) throws -> [String] {
        let sql = """
        SELECT pos.code
        FROM lemma_pos
        JOIN pos ON lemma_pos.pos_id = pos.id
        WHERE lemma_pos.lemma_id = ?
        ORDER BY lemma_pos.is_primary DESC, pos.code ASC;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lemmaID)

        var codes: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let code = stringColumn(statement, index: 0) {
                codes.append(code)
            }
        }
        return codes
    }

    private func fetchSenseGroups(for lemmaID: Int64) throws -> [SenseGroup] {
        let sql = """
        SELECT sense.id, sense.gloss, sense.definition, sense.sense_order, pos.code
        FROM sense
        LEFT JOIN pos ON sense.pos_id = pos.id
        WHERE sense.lemma_id = ?
        ORDER BY pos.code, sense.sense_order, sense.id;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lemmaID)

        var groups: [String: [SenseItem]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let gloss = stringColumn(statement, index: 1) ?? ""
            let definition = stringColumn(statement, index: 2)
            let order = Int(sqlite3_column_int(statement, 3))
            let posCode = stringColumn(statement, index: 4) ?? "other"
            let item = SenseItem(id: id, gloss: gloss, definition: definition, order: order)
            groups[posCode, default: []].append(item)
        }

        return groups
            .map { key, senses in
                let sorted = senses.sorted { lhs, rhs in
                    if lhs.order != rhs.order { return lhs.order < rhs.order }
                    return lhs.id < rhs.id
                }
                return SenseGroup(id: key, posCode: key, senses: sorted)
            }
            .sorted { $0.posCode < $1.posCode }
    }

    func fetchVocabularyLists() throws -> [VocabularyList] {
        let sql = "SELECT title, description FROM vocabulary_list ORDER BY title;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var lists: [VocabularyList] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let title = stringColumn(statement, index: 0) ?? ""
            let description = stringColumn(statement, index: 1)
            lists.append(VocabularyList(id: title, title: title, description: description))
        }
        return lists
    }

    func updateFavorite(lemmaID: Int64, isFavorite: Bool) throws {
        if isReadOnly { throw SQLiteStoreError.readOnly }
        let sql = "UPDATE lemma SET is_favorite = ? WHERE id = ?;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, isFavorite ? 1 : 0)
        sqlite3_bind_int64(statement, 2, lemmaID)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.stepFailed(errorMessage())
        }
    }

    func updateLearningStatus(lemmaID: Int64, status: LearningStatus) throws {
        if isReadOnly { throw SQLiteStoreError.readOnly }
        let sql = "UPDATE lemma SET learning_status = ? WHERE id = ?;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(status.rawValue))
        sqlite3_bind_int64(statement, 2, lemmaID)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.stepFailed(errorMessage())
        }
    }

    func fetchNounForms(lemmaID: Int64) throws -> [NounForm] {
        guard let posID = posIDByCode["noun"] else { return [] }
        let sql = """
        SELECT form.id, form.form, form.number, form.grammatical_case, form.gender,
               COALESCE(dialect.code, 'attic') AS dialect
        FROM form
        LEFT JOIN dialect ON form.dialect_id = dialect.id
        WHERE form.lemma_id = ? AND form.pos_id = ?
        ORDER BY form.id;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lemmaID)
        sqlite3_bind_int64(statement, 2, posID)

        var forms: [NounForm] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let form = stringColumn(statement, index: 1) ?? ""
            let number = stringColumn(statement, index: 2)
            let grammaticalCase = stringColumn(statement, index: 3)
            let gender = stringColumn(statement, index: 4)
            let dialect = stringColumn(statement, index: 5) ?? "attic"
            forms.append(NounForm(id: id, form: form, number: number, grammaticalCase: grammaticalCase, gender: gender, dialect: dialect))
        }
        return forms
    }

    func fetchVerbForms(lemmaID: Int64) throws -> [VerbForm] {
        guard let posID = posIDByCode["verb"] else { return [] }
        let sql = """
        SELECT form.id, form.form, form.person, form.number, form.tense, form.mood, form.voice,
               COALESCE(dialect.code, 'attic') AS dialect
        FROM form
        LEFT JOIN dialect ON form.dialect_id = dialect.id
        WHERE form.lemma_id = ? AND form.pos_id = ?
        ORDER BY form.id;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lemmaID)
        sqlite3_bind_int64(statement, 2, posID)

        var forms: [VerbForm] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let form = stringColumn(statement, index: 1) ?? ""
            let person = stringColumn(statement, index: 2)
            let number = stringColumn(statement, index: 3)
            let tense = stringColumn(statement, index: 4)
            let mood = stringColumn(statement, index: 5)
            let voice = stringColumn(statement, index: 6)
            let dialect = stringColumn(statement, index: 7) ?? "attic"
            forms.append(VerbForm(id: id, form: form, person: person, number: number, tense: tense, mood: mood, voice: voice, dialect: dialect))
        }
        return forms
    }
}
