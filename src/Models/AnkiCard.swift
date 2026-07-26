import Foundation

/// カード表面の表現タイプ (問題 / 単語 / 穴埋め)
public enum CardFrontType: String, Codable, CaseIterable, Identifiable, Sendable {
    case question = "問題"
    case word = "単語"
    case cloze = "穴埋め"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .question: return "questionmark.circle.fill"
        case .word: return "character.book.closed.fill"
        case .cloze: return "eye.slash.fill"
        }
    }
    
    public var badgeLabel: String {
        switch self {
        case .question: return "QUESTION"
        case .word: return "WORD"
        case .cloze: return "CLOZE (穴埋め)"
        }
    }
}

/// 正誤判定・クオリティ評価 (◯, △, ✕ の3択)
public enum Rating: Int, Codable, CaseIterable, Sendable {
    case incorrect = 1  // ✕ (バツ・不正解)
    case doubtful = 2   // △ (三角・惜しい / 自信なし)
    case correct = 3    // ◯ (マル・正解)
    
    public var symbol: String {
        switch self {
        case .incorrect: return "✕"
        case .doubtful: return "△"
        case .correct: return "◯"
        }
    }
    
    public var label: String {
        switch self {
        case .incorrect: return "不正解 (✕)"
        case .doubtful: return "惜しい (△)"
        case .correct: return "正解 (◯)"
        }
    }
}

/// 単一の暗記カードモデル
public struct AnkiCard: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var frontText: String
    public var backText: String
    public var frontType: CardFrontType      // 表面タイプ (問題 / 単語 / 穴埋め)
    
    // 裏面詳細拡張フィールド
    public var explanation1: String         // 解説1
    public var explanation2: String         // 解説2
    public var explanation3: String         // 解説3
    public var japaneseTranslation: String  // 日本語訳 / 和訳
    public var exampleSentence: String      // 例文
    public var exampleTranslation: String   // 例文の和訳
    public var synonyms: String            // 類義語
    public var antonyms: String            // 反対語・対義語
    
    public var frontImageURLs: [String] // 表面の複数画像
    public var backImageURLs: [String]  // 裏面の複数画像
    public var frontAudioURL: String?   // 表面の音声URL/ファイルパス
    public var backAudioURL: String?    // 裏面の音声URL/ファイルパス
    public var speechLanguage: String?  // 読み上げ言語 ("en-US", "ja-JP" など)
    public var mainCategory: String     // メインカテゴリー (例: 文法, IT, 元素)
    public var subCategory: String      // サブカテゴリー (例: 動詞, ネットワーク, アルカリ金属)
    public var tags: [String]
    public var isFavorite: Bool
    public var userNotes: String        // ユーザー個人メモ
    
    // 間隔反復 (Spaced Repetition) および学習履歴用フィールド
    public var reps: Int
    public var intervalDays: Int
    public var easeFactor: Double
    public var dueDate: Date
    public var createdAt: Date
    public var lastStudiedAt: Date?         // 個別カードの最終学習日時
    public var lastRating: Rating?
    public var wrongCount: Int              // 不正解(✕)累計回数
    public var doubtfulCount: Int           // 惜しい(△)累計回数
    public var consecutiveCorrectCount: Int // 連続◯(正解)回数

    public init(
        id: UUID = UUID(),
        frontText: String,
        backText: String,
        frontType: CardFrontType = .question,
        explanation1: String = "",
        explanation2: String = "",
        explanation3: String = "",
        japaneseTranslation: String = "",
        exampleSentence: String = "",
        exampleTranslation: String = "",
        synonyms: String = "",
        antonyms: String = "",
        frontImageURLs: [String] = [],
        backImageURLs: [String] = [],
        frontAudioURL: String? = nil,
        backAudioURL: String? = nil,
        speechLanguage: String? = nil,
        mainCategory: String = "",
        subCategory: String = "",
        tags: [String] = [],
        isFavorite: Bool = false,
        userNotes: String = "",
        reps: Int = 0,
        intervalDays: Int = 0,
        easeFactor: Double = 2.5,
        dueDate: Date = Date(),
        createdAt: Date = Date(),
        lastStudiedAt: Date? = nil,
        lastRating: Rating? = nil,
        wrongCount: Int = 0,
        doubtfulCount: Int = 0,
        consecutiveCorrectCount: Int = 0
    ) {
        self.id = id
        self.frontText = frontText
        self.backText = backText
        self.frontType = frontType
        self.explanation1 = explanation1
        self.explanation2 = explanation2
        self.explanation3 = explanation3
        self.japaneseTranslation = japaneseTranslation
        self.exampleSentence = exampleSentence
        self.exampleTranslation = exampleTranslation
        self.synonyms = synonyms
        self.antonyms = antonyms
        self.frontImageURLs = frontImageURLs
        self.backImageURLs = backImageURLs
        self.frontAudioURL = frontAudioURL
        self.backAudioURL = backAudioURL
        self.speechLanguage = speechLanguage
        self.mainCategory = mainCategory
        self.subCategory = subCategory
        self.tags = tags
        self.isFavorite = isFavorite
        self.userNotes = userNotes
        self.reps = reps
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.lastStudiedAt = lastStudiedAt
        self.lastRating = lastRating
        self.wrongCount = wrongCount
        self.doubtfulCount = doubtfulCount
        self.consecutiveCorrectCount = consecutiveCorrectCount
    }
    
    /// カテゴリー表示用表示文字列（例: "英語 ❯ 単語"）
    public var categoryPath: String? {
        if !mainCategory.isEmpty && !subCategory.isEmpty {
            return "\(mainCategory) ❯ \(subCategory)"
        } else if !mainCategory.isEmpty {
            return mainCategory
        } else if !subCategory.isEmpty {
            return subCategory
        }
        return nil
    }
    
    /// 未学習カードか (SRS-04: 一度も復習していない lastStudiedAt == nil で判定)
    public var isUnlearned: Bool {
        lastStudiedAt == nil
    }
    
    /// 4回連続◯（正解）を達成して習得済みか
    public var isMasteredFourTimes: Bool {
        consecutiveCorrectCount >= 4
    }
    
    /// 4回連続◯を達成しているが、30日以上経過していてメンテナンス復習が必要か (SRS-06: Calendar API で判定)
    public var isMaintenanceNeeded: Bool {
        guard isMasteredFourTimes, let last = lastStudiedAt else { return false }
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return last < thirtyDaysAgo
    }
    
    /// フィルター除外対象としての完全マスターアクティブ判定 (30日経過している場合は復元)
    public var isFullyMasteredActive: Bool {
        isMasteredFourTimes && !isMaintenanceNeeded
    }
    
    /// 今日学習したか
    public var isStudiedToday: Bool {
        guard let last = lastStudiedAt else { return false }
        return Calendar.current.isDateInToday(last)
    }
    
    /// 昨日学習したか
    public var isStudiedYesterday: Bool {
        guard let last = lastStudiedAt else { return false }
        return Calendar.current.isDateInYesterday(last)
    }
    
    /// 1週間以内に学習したか (SRS-06: Calendar API で判定)
    public var isStudiedWithinOneWeek: Bool {
        guard let last = lastStudiedAt else { return false }
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return last >= oneWeekAgo
    }
    
    // --- 前回学習時の判定 ---
    public var isWrongTriangleLastTime: Bool {
        lastRating == .doubtful
    }
    
    public var isWrongCrossLastTime: Bool {
        lastRating == .incorrect
    }
    
    public var isWrongTriangleOrCrossLastTime: Bool {
        isWrongTriangleLastTime || isWrongCrossLastTime
    }
    
    // --- 過去累計（一度でも...）の判定 ---
    public var hasEverBeenTriangle: Bool {
        doubtfulCount > 0 || isWrongTriangleLastTime
    }
    
    public var hasEverBeenCross: Bool {
        wrongCount > 0 || isWrongCrossLastTime
    }
    
    public var hasEverBeenTriangleOrCross: Bool {
        hasEverBeenTriangle || hasEverBeenCross
    }
}
