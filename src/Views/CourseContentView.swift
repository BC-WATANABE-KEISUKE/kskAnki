import SwiftUI

/// コース内コンテンツ（カード）一覧・検索・編集・削除ビュー (UI-08 空状態検索フィードバック対応)
@available(iOS 17.0, macOS 14.0, *)
public struct CourseContentView: View {
    @Binding public var cards: [AnkiCard]
    @State private var searchText: String = ""
    @State private var editingCard: AnkiCard?
    @State private var isAddSheetPresented: Bool = false
    
    public let onAddCards: ([AnkiCard]) -> Void
    public let onDeleteCard: (UUID) -> Void
    public let onUpdateCard: (AnkiCard) -> Void
    
    public init(
        cards: Binding<[AnkiCard]>,
        onAddCards: @escaping ([AnkiCard]) -> Void,
        onDeleteCard: @escaping (UUID) -> Void,
        onUpdateCard: @escaping (AnkiCard) -> Void
    ) {
        self._cards = cards
        self.onAddCards = onAddCards
        self.onDeleteCard = onDeleteCard
        self.onUpdateCard = onUpdateCard
    }
    
    // 検索テキスト適用後のカード一覧
    private var filteredCards: [AnkiCard] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return cards
        } else {
            return cards.filter { card in
                card.frontText.localizedCaseInsensitiveContains(query) ||
                card.backText.localizedCaseInsensitiveContains(query) ||
                card.japaneseTranslation.localizedCaseInsensitiveContains(query) ||
                card.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
    }
    
    public var body: some View {
        List {
            if cards.isEmpty {
                ContentUnavailableView(
                    "カードがありません",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("右上または下のボタンから新しいカードを追加してください。")
                )
            } else if filteredCards.isEmpty {
                // UI-08: 検索結果0件時の空状態フィードバック (Empty State)
                ContentUnavailableView(
                    "一致するカードが見つかりません",
                    systemImage: "magnifyingglass",
                    description: Text("\"\(searchText)\" に該当する単語・問題カードはありません。検索キーワードを変更してください。")
                )
            } else {
                ForEach(filteredCards) { card in
                    cardRow(card)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onDeleteCard(card.id)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                var updated = card
                                updated.isFavorite.toggle()
                                onUpdateCard(updated)
                            } label: {
                                Label(
                                    card.isFavorite ? "解除" : "お気に入り",
                                    systemImage: card.isFavorite ? "star.slash" : "star.fill"
                                )
                            }
                            .tint(.yellow)
                        }
                        .onTapGesture {
                            editingCard = card
                        }
                }
            }
        }
        .searchable(text: $searchText, prompt: "問題文・解答・タグで検索...")
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    isAddSheetPresented = true
                }) {
                    Label("カード追加", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AddCardView { newCards in
                onAddCards(newCards)
            }
        }
        .sheet(item: $editingCard) { card in
            EditCardView(card: card) { updatedCard in
                onUpdateCard(updatedCard)
            }
        }
    }
    
    private func cardRow(_ card: AnkiCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.frontText)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                if card.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }
            
            Text(card.backText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
