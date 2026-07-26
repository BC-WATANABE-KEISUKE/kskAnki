import Foundation
import os

private let logger = Logger(subsystem: "com.ksk.kskAnki", category: "Persistence")

/// ディスク保存用 DTO
public struct DeckStoreSnapshot: Codable, Sendable {
    public var folders: [CourseFolder]
    public var courses: [Course]
    public var studyLogs: [StudyLog]
    public var dailyGoalCardsCount: Int
}

/// 個別学習ログモデル (ARC-04 動的ストリーク計算用)
public struct StudyLog: Codable, Sendable, Identifiable {
    public var id: UUID
    public let cardId: UUID
    public let rating: Rating
    public let studiedAt: Date
    
    public init(id: UUID = UUID(), cardId: UUID, rating: Rating, studiedAt: Date = Date()) {
        self.id = id
        self.cardId = cardId
        self.rating = rating
        self.studiedAt = studiedAt
    }
}

/// ディスクへの非同期・直列化保存アクター (NEW2-02: 競合・データ上書き消失防止)
public actor PersistenceWriter {
    private let saveFileURL: URL
    
    public init(saveFileURL: URL) {
        self.saveFileURL = saveFileURL
    }
    
    public func write(_ snapshot: DeckStoreSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            // SEC-03: completeFileProtection オプションでデバイス暗号化保護を適用
            try data.write(to: saveFileURL, options: [.atomic, .completeFileProtection])
        } catch {
            logger.error("Failed to save DeckStore to disk: \(error.localizedDescription)")
        }
    }
}

/// デッキ＆コース＆フォルダデータ管理ストア (ARC-08: MainActor適合 & メインスレッド安全)
@MainActor
@Observable
public final class DeckStore {
    public var folders: [CourseFolder] = []
    public var courses: [Course] = []
    public var studyLogs: [StudyLog] = []
    
    // 日次学習目標プロパティ
    public var dailyGoalCardsCount: Int = 20
    
    // PERF-02: 本日の学習枚数 & ストリーク数をキャッシュ保持 (トップ画面カクツキ 54ms を解消)
    public private(set) var todayStudiedCardsCount: Int = 0
    public private(set) var streakDaysCount: Int = 0
    
    // NEW2-03: O(1) 差分更新用 Set キャッシュ
    private var studyDaysCache: Set<Date> = []
    
    private let customStorageURL: URL?
    
    // NEW2-02: 直列化保存アクター
    private let persistenceWriter: PersistenceWriter
    
    // NEW-14: 依存性注入イニシャライザ (テストで一時ディレクトリを指定し実 Documents 汚染を回避)
    public init(storageURL: URL? = nil) {
        self.customStorageURL = storageURL
        let targetURL = storageURL ?? (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("kskAnki_store.json") ?? FileManager.default.temporaryDirectory.appendingPathComponent("kskAnki_store.json"))
        self.persistenceWriter = PersistenceWriter(saveFileURL: targetURL)
        
        // NEW3-01: 「コース数0件」ではなく「保存ファイルが存在しない＝初回起動」でサンプルデータを投入
        let didLoad = loadFromDisk()
        if !didLoad {
            loadSampleData()
            saveToDiskSync()
        } else {
            recalculateMetrics()
        }
    }
    
    // PERF-02: メトリクスの初期化・再計算処理 (起動・ロード・復元・一括処理用)
    public func recalculateMetrics() {
        let calendar = Calendar.current
        self.todayStudiedCardsCount = studyLogs.filter { calendar.isDateInToday($0.studiedAt) }.count
        
        let studyDates = Set(studyLogs.map { calendar.startOfDay(for: $0.studiedAt) })
        self.studyDaysCache = studyDates
        self.streakDaysCount = computeStreak(from: studyDates)
    }
    
    private func computeStreak(from studyDates: Set<Date>) -> Int {
        let calendar = Calendar.current
        var currentStreak = 0
        var checkDate = calendar.startOfDay(for: Date())
        
        if !studyDates.contains(checkDate) {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        
        while studyDates.contains(checkDate) {
            currentStreak += 1
            guard let prevDate = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prevDate
        }
        
        return currentStreak
    }
    
    private var saveFileURL: URL {
        if let custom = customStorageURL {
            return custom
        }
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docDir = paths.first ?? FileManager.default.temporaryDirectory
        return docDir.appendingPathComponent("kskAnki_store.json")
    }
    
    // --- ディスク永続化 (NEW2-05: 同期保存と非同期保存の明確分離) ---
    
    /// 同期保存。書き込みの成否結果を返す (NEW2-05)
    @discardableResult
    public func saveToDiskSync() -> Bool {
        let snapshot = DeckStoreSnapshot(
            folders: folders,
            courses: courses,
            studyLogs: studyLogs,
            dailyGoalCardsCount: dailyGoalCardsCount
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: saveFileURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            logger.error("Failed to save DeckStore to disk: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 非同期スケジュール保存 (PersistenceWriter アクターによる直列化) (NEW2-05: 戻り値を Void にし型役割を正確化)
    public func saveToDisk(sync: Bool = false) {
        if sync {
            _ = saveToDiskSync()
            return
        }
        let snapshot = DeckStoreSnapshot(
            folders: folders,
            courses: courses,
            studyLogs: studyLogs,
            dailyGoalCardsCount: dailyGoalCardsCount
        )
        let writer = persistenceWriter
        Task {
            await writer.write(snapshot)
        }
    }
    
    @discardableResult
    public func loadFromDisk() -> Bool {
        guard FileManager.default.fileExists(atPath: saveFileURL.path) else {
            return false
        }
        do {
            let data = try Data(contentsOf: saveFileURL)
            let snapshot = try JSONDecoder().decode(DeckStoreSnapshot.self, from: data)
            self.folders = snapshot.folders
            self.courses = snapshot.courses
            self.studyLogs = snapshot.studyLogs
            self.dailyGoalCardsCount = snapshot.dailyGoalCardsCount
            recalculateMetrics()
            return true
        } catch {
            logger.error("Failed to load DeckStore from disk: \(error.localizedDescription)")
            return false
        }
    }
    
    // --- フォルダ操作 ---
    public func addFolder(_ folder: CourseFolder) {
        folders.append(folder)
        saveToDisk()
    }
    
    public func deleteFolder(_ folderId: UUID) {
        folders.removeAll { $0.id == folderId }
        courses.removeAll { $0.folderId == folderId }
        saveToDisk()
    }
    
    // --- コース操作 ---
    public func addCourse(_ course: Course) {
        courses.append(course)
        saveToDisk()
    }
    
    // NEW3-02: コース更新・削除時に無関係な recalculateMetrics() 全走査を排除
    public func updateCourse(_ updatedCourse: Course) {
        if let idx = courses.firstIndex(where: { $0.id == updatedCourse.id }) {
            courses[idx] = updatedCourse
            saveToDisk()
        }
    }
    
    public func deleteCourse(_ courseId: UUID) {
        courses.removeAll { $0.id == courseId }
        saveToDisk()
    }
    
    public func toggleArchiveCourse(_ courseId: UUID) {
        if let idx = courses.firstIndex(where: { $0.id == courseId }) {
            courses[idx].isArchived.toggle()
            saveToDisk()
        }
    }
    
    // --- 複数カード一括更新 API (NEW-05: 1セッションの保存を1回に集約) ---
    public func updateCardsInDeckBulk(_ updatedCards: [AnkiCard], inDeckId deckId: UUID) {
        var cardMap = [UUID: AnkiCard]()
        for card in updatedCards {
            cardMap[card.id] = card
        }
        
        for cIdx in 0..<courses.count {
            for dIdx in 0..<courses[cIdx].decks.count {
                if courses[cIdx].decks[dIdx].id == deckId {
                    for cardIdx in 0..<courses[cIdx].decks[dIdx].cards.count {
                        let cid = courses[cIdx].decks[dIdx].cards[cardIdx].id
                        if let newCard = cardMap[cid] {
                            courses[cIdx].decks[dIdx].cards[cardIdx] = newCard
                        }
                    }
                }
            }
        }
        
        saveToDisk()
    }
    
    // --- 学習ログ記録 & 一元管理 (NEW2-03: 真の O(1) 差分更新, NEW-17: ログ件数上限トリミング) ---
    public func recordStudy(cardId: UUID, rating: Rating, at date: Date = Date()) {
        let log = StudyLog(cardId: cardId, rating: rating, studiedAt: date)
        studyLogs.append(log)
        
        // NEW-17: ログ件数が上限 (10,000件) を超えた場合は古いログをトリミング
        if studyLogs.count > SRSParameters.maxStudyLogsCapacity {
            studyLogs.removeFirst(studyLogs.count - SRSParameters.maxStudyLogsCapacity)
        }
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            todayStudiedCardsCount += 1
        }
        
        let day = calendar.startOfDay(for: date)
        if studyDaysCache.insert(day).inserted {
            streakDaysCount = computeStreak(from: studyDaysCache)
        }
        
        saveToDisk()
    }
    
    // PERF-06: 全登録カード数の取得 (lazy カウント最適化による配列コピー排除)
    public var allCardsCount: Int {
        courses.lazy.flatMap { $0.decks.lazy.flatMap { $0.cards } }.count
    }
    
    // 全デッキ一覧の取得
    public var allDecks: [AnkiDeck] {
        courses.flatMap { $0.decks }
    }
    
    // --- サンプルデータ生成 ---
    private func loadSampleData() {
        let folderIT = CourseFolder(name: "Google Cloud / IT資格", themeColorHex: "#4285F4")
        let folderLang = CourseFolder(name: "語学・英単語", themeColorHex: "#EA4335")
        self.folders = [folderIT, folderLang]
        
        let card1 = AnkiCard(
            frontText: "Cloud Storage のストレージクラスで、アクセス頻度が月1回未満のコスト最適化クラスは？",
            backText: "Nearline Storage",
            frontType: .question,
            explanation1: "Nearline Storageは30日以上の保管が前提。月1回未満のアクセスに最適。",
            japaneseTranslation: "ニアライン・ストレージ",
            exampleSentence: "Use Nearline storage for data accessed less than once a month.",
            mainCategory: "Google Cloud",
            subCategory: "Cloud Storage",
            tags: ["ACE", "PCA", "頻出"]
        )
        let card2 = AnkiCard(
            frontText: "IAMにおける {{最小権限の原則}} を適用するために使用する事前定義ロールの選択指針は？",
            backText: "業務に必要な最小限のアクセス権を持つロールを割り当てる。",
            frontType: .cloze,
            explanation1: "基本ロール (Owner, Editor, Viewer) は広範すぎるため、事前定義ロールまたはカスタムロールを推奨。",
            japaneseTranslation: "最小権限の原則",
            mainCategory: "Google Cloud",
            subCategory: "IAM",
            tags: ["IAM", "セキュリティ"]
        )
        
        let deckGCP = AnkiDeck(name: "Google Cloud 基礎問題集", cards: [card1, card2])
        let courseACE = Course(title: "Google Cloud Associate Cloud Engineer (ACE) 対策", description: "ACE合格に必要な必須知識・CLIコマンド・IAM設計の重要カード集", decks: [deckGCP], folderId: folderIT.id)
        
        let card3 = AnkiCard(
            frontText: "Implementation",
            backText: "実装・実行・履行",
            frontType: .word,
            explanation1: "動詞 implement (実装する) の名詞形。",
            japaneseTranslation: "実装、実行",
            exampleSentence: "The implementation of the new Cloud architecture was successful.",
            mainCategory: "英語",
            subCategory: "IT英単語",
            tags: ["単語", "IT英語"]
        )
        
        let deckVocab = AnkiDeck(name: "IT・クラウド必須英単語", cards: [card3])
        let courseTOEIC = Course(title: "ITエンジニアのための実践英単語", description: "ドキュメント読解や海外チームとの連携に役立つ必須単語帳", decks: [deckVocab], folderId: folderLang.id)
        
        self.courses = [courseACE, courseTOEIC]
    }
}
