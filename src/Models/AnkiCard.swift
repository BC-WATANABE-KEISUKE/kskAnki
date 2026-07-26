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

// RFC-02: カード学習統計サブモデル
public struct CardStudyMetrics: Codable, Equatable, Sendable {
    public var reps: Int
    public var intervalDays: Int
    public var easeFactor: Double
    public var dueDate: Date
    public var createdAt: Date
    public var lastStudiedAt: Date?
    public var lastRating: Rating?
    public var wrongCount: Int
    public var doubtfulCount: Int
    public var consecutiveCorrectCount: Int
    
    public init(
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
}

// RFC-02: カード詳細解説 & メディアサブモデル
public struct CardDetails: Codable, Equatable, Sendable {
    public var explanation1: String
    public var explanation2: String
    public var explanation3: String
    public var japaneseTranslation: String
    public var exampleSentence: String
    public var exampleTranslation: String
    public var synonyms: String
    public var antonyms: String
    public var frontImageURLs: [String]
    public var backImageURLs: [String]
    public var frontAudioURL: String?
    public var backAudioURL: String?
    public var speechLanguage: String?
    public var mainCategory: String
    public var subCategory: String
    public var tags: [String]
    public var isFavorite: Bool
    public var userNotes: String
    
    public init(
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
        userNotes: String = ""
    ) {
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
    }
}

/// 単一の暗記カードモデル (RFC-02: サブモデル責任分解 & 既存API完全維持)
public struct AnkiCard: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var frontText: String
    public var backText: String
    public var frontType: CardFrontType
    
    // サブモデル構造体
    public var details: CardDetails
    public var metrics: CardStudyMetrics
    
    // 既存プロパティへのフォワードアクセサ (後方互換性の完全維持)
    public var explanation1: String { get { details.explanation1 } set { details.explanation1 = newValue } }
    public var explanation2: String { get { details.explanation2 } set { details.explanation2 = newValue } }
    public var explanation3: String { get { details.explanation3 } set { details.explanation3 = newValue } }
    public var japaneseTranslation: String { get { details.japaneseTranslation } set { details.japaneseTranslation = newValue } }
    public var exampleSentence: String { get { details.exampleSentence } set { details.exampleSentence = newValue } }
    public var exampleTranslation: String { get { details.exampleTranslation } set { details.exampleTranslation = newValue } }
    public var synonyms: String { get { details.synonyms } set { details.synonyms = newValue } }
    public var antonyms: String { get { details.antonyms } set { details.antonyms = newValue } }
    public var frontImageURLs: [String] { get { details.frontImageURLs } set { details.frontImageURLs = newValue } }
    public var backImageURLs: [String] { get { details.backImageURLs } set { details.backImageURLs = newValue } }
    public var frontAudioURL: String? { get { details.frontAudioURL } set { details.frontAudioURL = newValue } }
    public var backAudioURL: String? { get { details.backAudioURL } set { details.backAudioURL = newValue } }
    public var speechLanguage: String? { get { details.speechLanguage } set { details.speechLanguage = newValue } }
    public var mainCategory: String { get { details.mainCategory } set { details.mainCategory = newValue } }
    public var subCategory: String { get { details.subCategory } set { details.subCategory = newValue } }
    public var tags: [String] { get { details.tags } set { details.tags = newValue } }
    public var isFavorite: Bool { get { details.isFavorite } set { details.isFavorite = newValue } }
    public var userNotes: String { get { details.userNotes } set { details.userNotes = newValue } }
    
    public var reps: Int { get { metrics.reps } set { metrics.reps = newValue } }
    public var intervalDays: Int { get { metrics.intervalDays } set { metrics.intervalDays = newValue } }
    public var easeFactor: Double { get { metrics.easeFactor } set { metrics.easeFactor = newValue } }
    public var dueDate: Date { get { metrics.dueDate } set { metrics.dueDate = newValue } }
    public var createdAt: Date { get { metrics.createdAt } set { metrics.createdAt = newValue } }
    public var lastStudiedAt: Date? { get { metrics.lastStudiedAt } set { metrics.lastStudiedAt = newValue } }
    public var lastRating: Rating? { get { metrics.lastRating } set { metrics.lastRating = newValue } }
    public var wrongCount: Int { get { metrics.wrongCount } set { metrics.wrongCount = newValue } }
    public var doubtfulCount: Int { get { metrics.doubtfulCount } set { metrics.doubtfulCount = newValue } }
    public var consecutiveCorrectCount: Int { get { metrics.consecutiveCorrectCount } set { metrics.consecutiveCorrectCount = newValue } }
    
    // 主イニシャライザ
    public init(
        id: UUID = UUID(),
        frontText: String,
        backText: String,
        frontType: CardFrontType = .question,
        details: CardDetails = CardDetails(),
        metrics: CardStudyMetrics = CardStudyMetrics()
    ) {
        self.id = id
        self.frontText = frontText
        self.backText = backText
        self.frontType = frontType
        self.details = details
        self.metrics = metrics
    }
    
    // 互換性イニシャライザ
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
        self.details = CardDetails(
            explanation1: explanation1,
            explanation2: explanation2,
            explanation3: explanation3,
            japaneseTranslation: japaneseTranslation,
            exampleSentence: exampleSentence,
            exampleTranslation: exampleTranslation,
            synonyms: synonyms,
            antonyms: antonyms,
            frontImageURLs: frontImageURLs,
            backImageURLs: backImageURLs,
            frontAudioURL: frontAudioURL,
            backAudioURL: backAudioURL,
            speechLanguage: speechLanguage,
            mainCategory: mainCategory,
            subCategory: subCategory,
            tags: tags,
            isFavorite: isFavorite,
            userNotes: userNotes
        )
        self.metrics = CardStudyMetrics(
            reps: reps,
            intervalDays: intervalDays,
            easeFactor: easeFactor,
            dueDate: dueDate,
            createdAt: createdAt,
            lastStudiedAt: lastStudiedAt,
            lastRating: lastRating,
            wrongCount: wrongCount,
            doubtfulCount: doubtfulCount,
            consecutiveCorrectCount: consecutiveCorrectCount
        )
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
