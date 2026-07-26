import Foundation

/// カードのコレクション（単語帳・デッキ）
public struct AnkiDeck: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var description: String
    public var cards: [AnkiCard]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        cards: [AnkiCard] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.cards = cards
        self.createdAt = createdAt
    }
    
    /// 本日学習対象（復習期日が来ている）のカード一覧
    public var dueCards: [AnkiCard] {
        let now = Date()
        return cards.filter { $0.dueDate <= now }
    }
}
