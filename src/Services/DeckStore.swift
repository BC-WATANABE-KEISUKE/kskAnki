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
    
    // PERF-02: メトリクスの再計算・更新処理
    public func recalculateMetrics() {
        let calendar = Calendar.current
        self.todayStudiedCardsCount = studyLogs.filter { calendar.isDateInToday($0.studiedAt) }.count
        
        guard !studyLogs.isEmpty else {
            self.streakDaysCount = 0
            return
        }
        
        let studyDates = Set(studyLogs.map { calendar.startOfDay(for: $0.studiedAt) })
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        
        if !studyDates.contains(checkDate) {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate), studyDates.contains(yesterday) {
                checkDate = yesterday
            } else {
                self.streakDaysCount = 0
                return
            }
        }
        
        while studyDates.contains(checkDate) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previousDay
        }
        
        self.streakDaysCount = streak
    }
    
    // 全コースから集計導出される全デッキ一覧 (ARC-01 一元化)
    public var allDecks: [AnkiDeck] {
        courses.flatMap(\.decks)
    }
    
    // 全コース・デッキに含まれる総カード数
    public var allCardsCount: Int {
        allDecks.reduce(0) { $0 + $1.cards.count }
    }
    
    private let saveFileURL: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docDir = paths.first ?? FileManager.default.temporaryDirectory
        return docDir.appendingPathComponent("kskAnki_store.json")
    }()
    
    public init(folders: [CourseFolder] = [], courses: [Course] = []) {
        if !loadFromDisk() {
            self.folders = folders.isEmpty ? DeckStore.sampleFolders : folders
            self.courses = courses.isEmpty ? DeckStore.sampleCourses(folders: self.folders) : courses
            saveToDisk()
        }
        recalculateMetrics()
    }
    
    // --- ディスク永続化 (PERF-03: メインスレッドをブロックしないバックグラウンド非同期保存 & 同期保存オプション) ---
    @discardableResult
    public func saveToDisk(sync: Bool = false) -> Bool {
        let snapshot = DeckStoreSnapshot(
            folders: folders,
            courses: courses,
            studyLogs: studyLogs,
            dailyGoalCardsCount: dailyGoalCardsCount
        )
        let targetURL = saveFileURL
        
        if sync {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: targetURL, options: [.atomic, .completeFileProtection])
            } catch {
                logger.error("Failed to save DeckStore to disk: \(error.localizedDescription)")
            }
        } else {
            Task.detached(priority: .utility) {
                do {
                    let data = try JSONEncoder().encode(snapshot)
                    // SEC-03: completeFileProtection オプションでデバイス暗号化保護を適用
                    try data.write(to: targetURL, options: [.atomic, .completeFileProtection])
                } catch {
                    logger.error("Failed to save DeckStore to disk: \(error.localizedDescription)")
                }
            }
        }
        return true
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
    
    // --- コース操作 ---
    public func addCourse(_ course: Course) {
        courses.append(course)
        saveToDisk()
    }
    
    public func updateCourse(_ course: Course) {
        if let idx = courses.firstIndex(where: { $0.id == course.id }) {
            courses[idx] = course
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
    
    // --- カード & デッキ操作 (ARC-04: 学習ログ追加) ---
    public func addCard(_ card: AnkiCard, toDeckId deckId: UUID) {
        for cIdx in courses.indices {
            for dIdx in courses[cIdx].decks.indices {
                if courses[cIdx].decks[dIdx].id == deckId {
                    courses[cIdx].decks[dIdx].cards.append(card)
                    courses[cIdx].updatedAt = Date()
                    saveToDisk()
                    return
                }
            }
        }
    }
    
    // NEW-02: 明示的な学習ログ記録 API (コース学習 & マイ単語帳学習共通)
    public func recordStudy(cardId: UUID, rating: Rating, at date: Date = Date()) {
        let log = StudyLog(cardId: cardId, rating: rating, studiedAt: date)
        studyLogs.append(log)
        recalculateMetrics()
        saveToDisk()
    }
    
    // NEW-05: 1セッションの複数カード成果を一括反映し、ディスク保存を1回に集約
    public func updateCardsInDeckBulk(_ updatedCards: [AnkiCard], inDeckId: UUID) {
        var didModify = false
        for cIdx in courses.indices {
            for dIdx in courses[cIdx].decks.indices {
                if courses[cIdx].decks[dIdx].id == inDeckId {
                    for card in updatedCards {
                        if let cardIdx = courses[cIdx].decks[dIdx].cards.firstIndex(where: { $0.id == card.id }) {
                            courses[cIdx].decks[dIdx].cards[cardIdx] = card
                            didModify = true
                        }
                    }
                    if didModify {
                        courses[cIdx].updatedAt = Date()
                        saveToDisk() // 1セッション全体の更新に対して最後に1回だけ保存
                        return
                    }
                }
            }
        }
    }
    
    public func updateCard(_ card: AnkiCard, inDeckId deckId: UUID) {
        for cIdx in courses.indices {
            for dIdx in courses[cIdx].decks.indices {
                if courses[cIdx].decks[dIdx].id == deckId {
                    if let cardIdx = courses[cIdx].decks[dIdx].cards.firstIndex(where: { $0.id == card.id }) {
                        courses[cIdx].decks[dIdx].cards[cardIdx] = card
                        courses[cIdx].updatedAt = Date()
                        saveToDisk()
                        return
                    }
                }
            }
        }
    }
    
    // サンプルフォルダ定義
    public static var sampleFolders: [CourseFolder] {
        return [
            CourseFolder(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "語学学習", iconName: "globe.americas.fill"),
            CourseFolder(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "IT・資格試験", iconName: "cpu.fill")
        ]
    }
    
    // サンプルコース定義
    public static func sampleCourses(folders: [CourseFolder]) -> [Course] {
        let langFolderId = folders.first(where: { $0.name == "語学学習" })?.id
        let itFolderId = folders.first(where: { $0.name == "IT・資格試験" })?.id
        
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)
        
        let aceDeckCards: [AnkiCard] = [
            AnkiCard(
                frontText: "Identity-Aware Proxy (IAP)",
                backText: "IAP",
                frontType: .word,
                explanation1: "VPNを使わずに、HTTPSやSSH/RDPによるVMへのアクセスをユーザーのGoogleアカウントとコンテキストに基づき安全に制御・認可するサービス。",
                explanation2: "ファイアウォールルールでは 35.235.240.0/20 からのアクセスを許可する必要がある。",
                japaneseTranslation: "Identity-Aware Proxy",
                mainCategory: "Google Cloud",
                subCategory: "IAM・セキュリティ",
                tags: ["ACE", "最頻出"]
            ),
            AnkiCard(
                frontText: "GCEにおいてアクセス制限の鉄則として推奨されるのは{{事前定義されたロール}}である。",
                backText: "事前定義されたロール (Predefined Roles)",
                frontType: .cloze,
                explanation1: "基本ロール (Owner, Editor, Viewer) は権限が強すぎるため使わない。最小権限の原則を満たすベストプラクティス。",
                japaneseTranslation: "roles/compute.networkAdmin など細かく調整されたロールが正解。",
                mainCategory: "Google Cloud",
                subCategory: "IAM・セキュリティ",
                tags: ["IAM", "ACE"]
            )
        ]
        
        let aceDeck = AnkiDeck(
            name: "Google Cloud ACE 重要用語・問題集",
            description: "Associate Cloud Engineer 資格試験必須用語＆コマンド",
            cards: aceDeckCards
        )

        let englishDeck = AnkiDeck(
            name: "TOEIC頻出英単語 800点レベル",
            description: "スコア直結の必須語彙",
            cards: [
                AnkiCard(
                    frontText: "Implementation",
                    backText: "実行、実装 (名詞)",
                    frontType: .word,
                    explanation1: "プロジェクト計画やソフトウェア開発における『仕様をコード化・実行するプロセス』を指します。",
                    japaneseTranslation: "実装、実行、履行",
                    exampleSentence: "The implementation of the new policy will begin next month.",
                    exampleTranslation: "新方針の実行は来月から始まります。",
                    mainCategory: "英語",
                    subCategory: "ビジネス単語",
                    tags: ["TOEIC"],
                    lastStudiedAt: now
                )
            ]
        )

        return [
            Course(
                title: "Google Cloud 認定 Associate Cloud Engineer (ACE)",
                description: "GCPの必須サービス・IAM・CLIコマンド・インフラ完全網羅",
                iconName: "cloud.fill",
                themeColorHex: "#4285F4",
                decks: [aceDeck],
                folderId: itFolderId,
                lastStudiedAt: now,
                updatedAt: now
            ),
            Course(
                title: "英会話・TOEICマスターコース",
                description: "日常会話からビジネス英語まで幅広くカバー",
                iconName: "globe.americas.fill",
                themeColorHex: "#FF9500",
                decks: [englishDeck],
                folderId: langFolderId,
                lastStudiedAt: now,
                updatedAt: yesterday ?? now
            )
        ]
    }
}
