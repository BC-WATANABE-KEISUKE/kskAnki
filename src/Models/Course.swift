import Foundation

/// コース並べ替えオプション
public enum CourseSortOption: String, CaseIterable, Identifiable, Sendable {
    case nameAsc = "名前順"
    case lastStudied = "最近学習した順"
    case updatedAt = "更新日順"
    
    public var id: String { self.rawValue }
}

/// 学習コースモデル
public struct Course: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var description: String
    public var iconName: String
    public var themeColorHex: String
    public var decks: [AnkiDeck]
    public var folderId: UUID?
    public var isArchived: Bool            // アーカイブフラグ
    public var lastStudiedAt: Date?
    public var updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        iconName: String = "book.fill",
        themeColorHex: String = "#007AFF",
        decks: [AnkiDeck] = [],
        folderId: UUID? = nil,
        isArchived: Bool = false,
        lastStudiedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.iconName = iconName
        self.themeColorHex = themeColorHex
        self.decks = decks
        self.folderId = folderId
        self.isArchived = isArchived
        self.lastStudiedAt = lastStudiedAt
        self.updatedAt = updatedAt
    }
    
    /// 総カード数
    public var totalCardsCount: Int {
        decks.reduce(0) { $0 + $1.cards.count }
    }
}
