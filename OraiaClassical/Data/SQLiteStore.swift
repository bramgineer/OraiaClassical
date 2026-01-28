import Foundation
import SQLite3

enum SQLiteStoreError: Error, LocalizedError {
    case databaseNotFound
    case userDatabaseNotFound
    case openFailed(String)
    case userDatabaseOpenFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case readOnly

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "Database resource not found."
        case .userDatabaseNotFound:
            return "User database not available."
        case .openFailed(let message):
            return "Failed to open database: \(message)"
        case .userDatabaseOpenFailed(let message):
            return "Failed to open user database: \(message)"
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
    private var userDb: OpaquePointer?
    private var posIDByCode: [String: Int64] = [:]
    private(set) var isReadOnly: Bool = false

    private let userSchemaSQL = """
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS vocabulary_list (
      title TEXT PRIMARY KEY,
      description TEXT
    );

    CREATE TABLE IF NOT EXISTS vocabulary_list_entry (
      vocabulary_list TEXT NOT NULL,
      lemma INTEGER NOT NULL,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (vocabulary_list, lemma),
      FOREIGN KEY (vocabulary_list) REFERENCES vocabulary_list(title) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS lemma_user_state (
      lemma INTEGER PRIMARY KEY,
      is_favorite INTEGER,
      learning_status INTEGER,
      updated_at TEXT DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_vocab_list_entry_list ON vocabulary_list_entry(vocabulary_list);
    CREATE INDEX IF NOT EXISTS idx_user_state_favorite ON lemma_user_state(is_favorite);
    CREATE INDEX IF NOT EXISTS idx_user_state_status ON lemma_user_state(learning_status);
    """

    init() {
        openDatabase()
        openUserDatabase()
        loadPosCodes()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
        if let userDb {
            sqlite3_close(userDb)
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

    private func openUserDatabase() {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let bundleID = Bundle.main.bundleIdentifier ?? "OraiaClassical"
        let directory = baseURL?.appendingPathComponent(bundleID, isDirectory: true)
        if let directory {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let dbURL = directory?.appendingPathComponent("user_data.sqlite")
        guard let path = dbURL?.path else { return }

        var connection: OpaquePointer?
        let result = sqlite3_open_v2(path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        if result != SQLITE_OK {
            sqlite3_close(connection)
            connection = nil
            return
        }

        userDb = connection
        if let userDb {
            sqlite3_busy_timeout(userDb, 2000)
            sqlite3_exec(userDb, "PRAGMA foreign_keys = ON;", nil, nil, nil)
            sqlite3_exec(userDb, userSchemaSQL, nil, nil, nil)
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
        errorMessage(db)
    }

    private func errorMessage(_ database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return "Unknown error" }
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

    private func prepareUser(_ sql: String) throws -> OpaquePointer? {
        guard let userDb else { throw SQLiteStoreError.userDatabaseNotFound }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(userDb, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(errorMessage(userDb))
        }
        return statement
    }

    private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private struct UserLemmaState {
        let isFavorite: Bool?
        let learningStatus: LearningStatus?
    }

    private func fetchUserState(for lemmaID: Int64) throws -> UserLemmaState? {
        guard let _ = userDb else { return nil }
        let sql = "SELECT is_favorite, learning_status FROM lemma_user_state WHERE lemma = ?;"
        let statement = try prepareUser(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lemmaID)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let favValue = sqlite3_column_type(statement, 0) == SQLITE_NULL ? nil : sqlite3_column_int(statement, 0)
        let statusValue = sqlite3_column_type(statement, 1) == SQLITE_NULL ? nil : sqlite3_column_int(statement, 1)
        let isFavorite = favValue == nil ? nil : (favValue == 1)
        let status = statusValue == nil ? nil : LearningStatus(rawValue: Int(statusValue!))
        return UserLemmaState(isFavorite: isFavorite, learningStatus: status)
    }

    private func fetchUserStates(for lemmaIDs: [Int64]) throws -> [Int64: UserLemmaState] {
        guard let _ = userDb else { return [:] }
        guard !lemmaIDs.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: lemmaIDs.count).joined(separator: ",")
        let sql = "SELECT lemma, is_favorite, learning_status FROM lemma_user_state WHERE lemma IN (\(placeholders));"
        let statement = try prepareUser(sql)
        defer { sqlite3_finalize(statement) }
        for (index, id) in lemmaIDs.enumerated() {
            sqlite3_bind_int64(statement, Int32(index + 1), id)
        }
        var result: [Int64: UserLemmaState] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let lemmaID = sqlite3_column_int64(statement, 0)
            let favValue = sqlite3_column_type(statement, 1) == SQLITE_NULL ? nil : sqlite3_column_int(statement, 1)
            let statusValue = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : sqlite3_column_int(statement, 2)
            let isFavorite = favValue == nil ? nil : (favValue == 1)
            let status = statusValue == nil ? nil : LearningStatus(rawValue: Int(statusValue!))
            result[lemmaID] = UserLemmaState(isFavorite: isFavorite, learningStatus: status)
        }
        return result
    }

    private func mergedLemma(_ lemma: LemmaSummary, userState: UserLemmaState?) -> LemmaSummary {
        let favorite = userState?.isFavorite ?? lemma.isFavorite
        let status = userState?.learningStatus ?? lemma.learningStatus
        return LemmaSummary(id: lemma.id, headword: lemma.headword, primaryPOS: lemma.primaryPOS, isFavorite: favorite, learningStatus: status)
    }

    private func fetchLemmaSummaries(ids: [Int64]) throws -> [LemmaSummary] {
        guard let _ = db else { throw SQLiteStoreError.databaseNotFound }
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = """
        SELECT lemma.id, lemma.headword, lemma.is_favorite, lemma.learning_status, pos.code
        FROM lemma
        LEFT JOIN lemma_pos ON lemma.id = lemma_pos.lemma_id AND lemma_pos.is_primary = 1
        LEFT JOIN pos ON lemma_pos.pos_id = pos.id
        WHERE lemma.id IN (\(placeholders))
        ORDER BY lemma.headword;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for (index, id) in ids.enumerated() {
            sqlite3_bind_int64(statement, Int32(index + 1), id)
        }
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
        let userStates = try fetchUserStates(for: results.map(\.id))
        return results.map { mergedLemma($0, userState: userStates[$0.id]) }
    }

    func fetchVocabQuizItems(listTitles: [String], includeFavorites: Bool, learningStatuses: [LearningStatus]) throws -> [VocabQuizItem] {
        let candidates = try fetchQuizCandidateIDs(
            listTitles: listTitles,
            includeFavorites: includeFavorites,
            learningStatuses: learningStatuses
        )
        guard !candidates.isEmpty else { return [] }

        let glosses = try fetchFirstGlosses(for: Array(candidates))
        let idsWithGloss = glosses.keys.sorted()
        guard !idsWithGloss.isEmpty else { return [] }

        let headwords = try fetchLemmaHeadwords(ids: idsWithGloss)
        var items: [VocabQuizItem] = []
        for id in idsWithGloss {
            guard let headword = headwords[id], let gloss = glosses[id], !gloss.isEmpty else { continue }
            items.append(VocabQuizItem(id: id, headword: headword, gloss: gloss))
        }
        return items
    }

    private func fetchQuizCandidateIDs(listTitles: [String], includeFavorites: Bool, learningStatuses: [LearningStatus]) throws -> Set<Int64> {
        var idSet: Set<Int64> = []

        if !listTitles.isEmpty {
            for title in listTitles {
                let ids = try fetchListLemmaIDs(listTitle: title)
                idSet.formUnion(ids)
            }
        }

        if includeFavorites {
            let ids = try fetchUserFavoriteLemmaIDs()
            idSet.formUnion(ids)
        }

        if !learningStatuses.isEmpty {
            for status in learningStatuses {
                let ids = try fetchUserLemmaIDs(with: status)
                idSet.formUnion(ids)
            }
        }

        return idSet
    }

    private func fetchLemmaHeadwords(ids: [Int64]) throws -> [Int64: String] {
        guard let _ = db else { throw SQLiteStoreError.databaseNotFound }
        guard !ids.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = "SELECT id, headword FROM lemma WHERE id IN (\(placeholders));"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for (index, id) in ids.enumerated() {
            sqlite3_bind_int64(statement, Int32(index + 1), id)
        }
        var result: [Int64: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let headword = stringColumn(statement, index: 1) ?? ""
            result[id] = headword
        }
        return result
    }

    private func fetchFirstGlosses(for ids: [Int64]) throws -> [Int64: String] {
        guard let _ = db else { throw SQLiteStoreError.databaseNotFound }
        guard !ids.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = """
        SELECT lemma_id, gloss, sense_order, id
        FROM sense
        WHERE lemma_id IN (\(placeholders))
        ORDER BY lemma_id, sense_order, id;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for (index, id) in ids.enumerated() {
            sqlite3_bind_int64(statement, Int32(index + 1), id)
        }
        var result: [Int64: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let lemmaID = sqlite3_column_int64(statement, 0)
            if result[lemmaID] != nil { continue }
            let gloss = stringColumn(statement, index: 1) ?? ""
            let trimmed = gloss.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            result[lemmaID] = trimmed
        }
        return result
    }

    private func fetchListLemmaIDs(listTitle: String) throws -> [Int64] {
        guard let _ = userDb else { return [] }
        let sql = "SELECT lemma FROM vocabulary_list_entry WHERE vocabulary_list = ? ORDER BY lemma;"
        let statement = try prepareUser(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (listTitle as NSString).utf8String, -1, nil)
        var ids: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            ids.append(sqlite3_column_int64(statement, 0))
        }
        return ids
    }

    private func fetchUserFavoriteLemmaIDs() throws -> [Int64] {
        guard let _ = userDb else { return [] }
        let sql = "SELECT lemma FROM lemma_user_state WHERE is_favorite = 1;"
        let statement = try prepareUser(sql)
        defer { sqlite3_finalize(statement) }
        var ids: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            ids.append(sqlite3_column_int64(statement, 0))
        }
        return ids
    }

    private func fetchUserLemmaIDs(with status: LearningStatus) throws -> [Int64] {
        guard let _ = userDb else { return [] }
        let sql = "SELECT lemma FROM lemma_user_state WHERE learning_status = ?;"
        let statement = try prepareUser(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(status.rawValue))
        var ids: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            ids.append(sqlite3_column_int64(statement, 0))
        }
        return ids
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
        let listIDs = (listTitle?.isEmpty == false) ? try fetchListLemmaIDs(listTitle: listTitle ?? "") : []
        let listIDSet = Set(listIDs)

        let sql = """
        SELECT lemma.id, lemma.headword, lemma.is_favorite, lemma.learning_status, pos.code
        FROM lemma
        LEFT JOIN lemma_pos ON lemma.id = lemma_pos.lemma_id AND lemma_pos.is_primary = 1
        LEFT JOIN pos ON lemma_pos.pos_id = pos.id
        WHERE lemma.headword LIKE ?
        """

        let withFiltersSQL: String = {
            var text = sql
            if favoritesOnly {
                text += " AND lemma.is_favorite = 1"
            }
            if learningStatus != nil {
                text += " AND lemma.learning_status = ?"
            }
            text += " ORDER BY lemma.headword LIMIT ?;"
            return text
        }()

        let statement = try prepare(withFiltersSQL)
        defer { sqlite3_finalize(statement) }

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

        var bindIndex: Int32 = 1
        sqlite3_bind_text(statement, bindIndex, (pattern as NSString).utf8String, -1, nil)
        bindIndex += 1
        if let learningStatus {
            sqlite3_bind_int(statement, bindIndex, Int32(learningStatus.rawValue))
            bindIndex += 1
        }
        sqlite3_bind_int(statement, bindIndex, Int32(limit))

        var combined: [LemmaSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let headword = stringColumn(statement, index: 1) ?? ""
            let isFavorite = sqlite3_column_int(statement, 2) == 1
            let statusValue = Int(sqlite3_column_int(statement, 3))
            let posCode = stringColumn(statement, index: 4)
            let status = LearningStatus(rawValue: statusValue) ?? .new
            combined.append(LemmaSummary(id: id, headword: headword, primaryPOS: posCode, isFavorite: isFavorite, learningStatus: status))
        }

        if favoritesOnly {
            let favoriteIDs = try fetchUserFavoriteLemmaIDs()
            let favorites = try fetchLemmaSummaries(ids: favoriteIDs)
            combined.append(contentsOf: favorites.filter { matchesQuery($0.headword, query: trimmed, mode: mode) })
        }

        if let learningStatus {
            let statusIDs = try fetchUserLemmaIDs(with: learningStatus)
            let statusMatches = try fetchLemmaSummaries(ids: statusIDs)
            combined.append(contentsOf: statusMatches.filter { matchesQuery($0.headword, query: trimmed, mode: mode) })
        }

        if trimmed.isEmpty, !listIDs.isEmpty {
            let listMatches = try fetchLemmaSummaries(ids: listIDs)
            combined.append(contentsOf: listMatches)
        }

        var unique: [Int64: LemmaSummary] = [:]
        for item in combined {
            unique[item.id] = item
        }
        var results = Array(unique.values)

        if !listIDSet.isEmpty {
            results = results.filter { listIDSet.contains($0.id) }
        }

        let userStates = try fetchUserStates(for: results.map(\.id))
        results = results.map { mergedLemma($0, userState: userStates[$0.id]) }

        if favoritesOnly {
            results = results.filter { $0.isFavorite }
        }
        if let learningStatus {
            results = results.filter { $0.learningStatus == learningStatus }
        }

        results.sort { $0.headword < $1.headword }
        if results.count > limit {
            results = Array(results.prefix(limit))
        }
        return results
    }

    private func matchesQuery(_ headword: String, query: String, mode: SearchMode) -> Bool {
        guard !query.isEmpty else { return true }
        let source = headword.lowercased()
        let target = query.lowercased()
        switch mode {
        case .startsWith:
            return source.hasPrefix(target)
        case .contains:
            return source.contains(target)
        }
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
        var isFavorite = sqlite3_column_int(lemmaStatement, 3) == 1
        let statusValue = Int(sqlite3_column_int(lemmaStatement, 4))
        var status = LearningStatus(rawValue: statusValue) ?? .new

        if let userState = try fetchUserState(for: id) {
            if let overrideFavorite = userState.isFavorite {
                isFavorite = overrideFavorite
            }
            if let overrideStatus = userState.learningStatus {
                status = overrideStatus
            }
        }

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
        let statement = try prepareUser(sql)
        defer { sqlite3_finalize(statement) }

        var lists: [VocabularyList] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let title = stringColumn(statement, index: 0) ?? ""
            let description = stringColumn(statement, index: 1)
            lists.append(VocabularyList(id: title, title: title, description: description))
        }
        return lists
    }

    func createVocabularyList(title: String, description: String?) throws {
        let sql = "INSERT OR IGNORE INTO vocabulary_list (title, description) VALUES (?, ?);"
        let statement = try prepareUser(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (title as NSString).utf8String, -1, nil)
        let descText = (description ?? "") as NSString
        sqlite3_bind_text(statement, 2, descText.utf8String, -1, nil)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.stepFailed(errorMessage(userDb))
        }
    }

    func fetchVocabularyListEntries(listTitle: String) throws -> [LemmaSummary] {
        let ids = try fetchListLemmaIDs(listTitle: listTitle)
        return try fetchLemmaSummaries(ids: ids)
    }

    func addLemmaToVocabularyList(listTitle: String, lemmaID: Int64) throws {
        let sql = "INSERT OR IGNORE INTO vocabulary_list_entry (vocabulary_list, lemma) VALUES (?, ?);"
        let statement = try prepareUser(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (listTitle as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, lemmaID)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.stepFailed(errorMessage(userDb))
        }
    }

    func removeLemmaFromVocabularyList(listTitle: String, lemmaID: Int64) throws {
        let sql = "DELETE FROM vocabulary_list_entry WHERE vocabulary_list = ? AND lemma = ?;"
        let statement = try prepareUser(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (listTitle as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, lemmaID)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.stepFailed(errorMessage(userDb))
        }
    }

    func deleteVocabularyList(title: String) throws {
        let deleteEntriesSQL = "DELETE FROM vocabulary_list_entry WHERE vocabulary_list = ?;"
        let entriesStatement = try prepareUser(deleteEntriesSQL)
        defer { sqlite3_finalize(entriesStatement) }
        sqlite3_bind_text(entriesStatement, 1, (title as NSString).utf8String, -1, nil)
        guard sqlite3_step(entriesStatement) == SQLITE_DONE else {
            throw SQLiteStoreError.stepFailed(errorMessage(userDb))
        }

        let deleteListSQL = "DELETE FROM vocabulary_list WHERE title = ?;"
        let listStatement = try prepareUser(deleteListSQL)
        defer { sqlite3_finalize(listStatement) }
        sqlite3_bind_text(listStatement, 1, (title as NSString).utf8String, -1, nil)
        guard sqlite3_step(listStatement) == SQLITE_DONE else {
            throw SQLiteStoreError.stepFailed(errorMessage(userDb))
        }
    }

    func updateFavorite(lemmaID: Int64, isFavorite: Bool) throws {
        try upsertUserState(lemmaID: lemmaID, isFavorite: isFavorite, learningStatus: nil)
    }

    func updateLearningStatus(lemmaID: Int64, status: LearningStatus) throws {
        try upsertUserState(lemmaID: lemmaID, isFavorite: nil, learningStatus: status)
    }

    private func upsertUserState(lemmaID: Int64, isFavorite: Bool?, learningStatus: LearningStatus?) throws {
        let sql = """
        INSERT INTO lemma_user_state (lemma, is_favorite, learning_status, updated_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(lemma) DO UPDATE SET
            is_favorite = COALESCE(excluded.is_favorite, lemma_user_state.is_favorite),
            learning_status = COALESCE(excluded.learning_status, lemma_user_state.learning_status),
            updated_at = CURRENT_TIMESTAMP;
        """
        let statement = try prepareUser(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lemmaID)
        if let isFavorite {
            sqlite3_bind_int(statement, 2, isFavorite ? 1 : 0)
        } else {
            sqlite3_bind_null(statement, 2)
        }
        if let learningStatus {
            sqlite3_bind_int(statement, 3, Int32(learningStatus.rawValue))
        } else {
            sqlite3_bind_null(statement, 3)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.stepFailed(errorMessage(userDb))
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
               form.verb_form_type,
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
            let verbFormType = stringColumn(statement, index: 7)
            let dialect = stringColumn(statement, index: 8) ?? "attic"
            forms.append(VerbForm(id: id, form: form, person: person, number: number, tense: tense, mood: mood, voice: voice, verbFormType: verbFormType, dialect: dialect))
        }
        return forms
    }
}
