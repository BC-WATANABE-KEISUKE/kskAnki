import SwiftUI

/// コース詳細トップ画面 (学習設定セッション / コンテンツ管理の切替)
@available(iOS 17.0, macOS 14.0, *)
public struct CourseDetailView: View {
    @State public var course: Course
    @State private var selectedTab: Int = 0 // 0: 学習スタート, 1: コンテンツ一覧
    
    // 学習設定ステート (SRS-01: デフォルトを復習日到来 .dueToday に設定)
    @State private var filterTarget: StudyFilterTarget = .dueToday
    @State private var batchSize: Int = 10 // 10, 20, 0 (全件)
    @State private var activeStudyDeck: AnkiDeck?
    
    // ARC-09: フィルタリング再計算のキャッシュ用ステート
    @State private var cachedMatchingCards: [AnkiCard] = []
    @State private var cachedTargetCards: [AnkiCard] = []
    
    // カード追加シート
    @State private var isAddCardSheetPresented: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    public let onSaveCourse: (Course) -> Void
    public let onRecordRating: (UUID, Rating) -> Void
    
    public init(
        course: Course,
        onRecordRating: @escaping (UUID, Rating) -> Void = { _, _ in },
        onSaveCourse: @escaping (Course) -> Void
    ) {
        self._course = State(initialValue: course)
        self.onRecordRating = onRecordRating
        self.onSaveCourse = onSaveCourse
    }
    
    // コース内すべてのカードを平坦に集計
    private var allCards: [AnkiCard] {
        course.decks.flatMap { $0.cards }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // セグメント切り替えバー
                Picker("画面モード", selection: $selectedTab) {
                    Text("学習スタート").tag(0)
                    Text("コンテンツ一覧 (\(allCards.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedTab == 0 {
                    studySetupView
                } else {
                    CourseContentView(
                        cards: Binding(
                            get: { allCards },
                            set: { updatedCards in
                                updateAllCards(updatedCards)
                            }
                        ),
                        onAddCards: { newCards in
                            addCardsToCourse(newCards)
                        },
                        onDeleteCard: { cardId in
                            deleteCardFromCourse(cardId)
                        },
                        onUpdateCard: { updatedCard in
                            updateSingleCardInCourse(updatedCard)
                        }
                    )
                }
            }
            .navigationTitle(course.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        isAddCardSheetPresented = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            #if os(iOS)
            .fullScreenCover(item: $activeStudyDeck) { studyDeck in
                CardStudyView(
                    deck: studyDeck,
                    onRecordRating: { cardId, rating in
                        // NEW-02: コース経由の学習でも StudyLog をリアルタイム保存
                        onRecordRating(cardId, rating)
                    },
                    onFinishSession: { sessionCards, ratings, shouldSave in
                        if shouldSave {
                            // NEW-05: 1セッション全体の成果をメモリ上で一括適用し、保存を1回に集約
                            updateCardsInCourseBulk(sessionCards)
                        }
                    }
                )
            }
            #else
            .sheet(item: $activeStudyDeck) { studyDeck in
                CardStudyView(
                    deck: studyDeck,
                    onRecordRating: { cardId, rating in
                        // NEW-02: コース経由の学習でも StudyLog をリアルタイム保存
                        onRecordRating(cardId, rating)
                    },
                    onFinishSession: { sessionCards, ratings, shouldSave in
                        if shouldSave {
                            // NEW-05: 1セッション全体の成果をメモリ上で一括適用し、保存を1回に集約
                            updateCardsInCourseBulk(sessionCards)
                        }
                    }
                )
            }
            #endif
            .sheet(isPresented: $isAddCardSheetPresented) {
                AddCardView { newCards in
                    addCardsToCourse(newCards)
                }
            }
            .onAppear {
                recalculateFilteredCards()
            }
            .onChange(of: filterTarget) {
                recalculateFilteredCards()
            }
            .onChange(of: batchSize) {
                recalculateFilteredCards()
            }
        }
    }
    
    // ARC-09: 再計算処理の分離・最適化
    private func recalculateFilteredCards() {
        let matchingConfig = StudyFilterConfig(target: filterTarget, batchSize: 0)
        let matching = matchingConfig.filterCards(allCards)
        
        let batchConfig = StudyFilterConfig(target: filterTarget, batchSize: batchSize)
        let target = batchConfig.filterCards(allCards)
        
        self.cachedMatchingCards = matching
        self.cachedTargetCards = target
    }
    
    // 1. 学習スタート設定モード画面
    private var studySetupView: some View {
        Form {
            // コースヘッダー情報
            Section {
                HStack(spacing: 16) {
                    Image(systemName: course.iconName)
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.blue)
                        .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(course.title)
                            .font(.headline)
                        Text(course.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // 対象条件選択 (リアルタイム枚数カウント表示)
            Section {
                Picker("対象のカード", selection: $filterTarget) {
                    ForEach(StudyFilterTarget.allCases) { target in
                        Text(target.rawValue).tag(target)
                    }
                }
                .pickerStyle(.menu)
                
                // FEAT-01: お気に入りカード集中学習ショートカット
                Button(action: {
                    filterTarget = .favorites
                    batchSize = 0 // 全件
                }) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text("★ お気に入りカードだけを全件復習")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                
                HStack {
                    Text(filterTarget.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("該当: \(cachedMatchingCards.count) 枚")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                }
                .padding(.top, 2)
            } header: {
                Text("学習対象条件 (何を選ぶか)")
            }
            
            // 学習枚数制限 (10枚, 20枚, 全件の3択)
            Section {
                Picker("一度に学習する枚数", selection: $batchSize) {
                    Text("10 枚").tag(10)
                    Text("20 枚").tag(20)
                    Text("全件 (\(cachedMatchingCards.count)枚)").tag(0)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("1回の学習枚数 (10枚 / 20枚 / 全件)")
            }
            
            // 学習対象カードのプレビュー＆巨大スタートボタン
            Section {
                VStack(spacing: 16) {
                    HStack {
                        Text("今回の学習セッション数:")
                            .font(.subheadline)
                        Spacer()
                        Text("\(cachedTargetCards.count) / \(cachedMatchingCards.count) 枚")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: startStudySession) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("学習を開始する")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(cachedTargetCards.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .disabled(cachedTargetCards.isEmpty)
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    // 学習開始セッション起動
    private func startStudySession() {
        guard !cachedTargetCards.isEmpty else { return }
        var updatedCourse = course
        updatedCourse.lastStudiedAt = Date()
        self.course = updatedCourse
        onSaveCourse(updatedCourse)
        
        let studyDeck = AnkiDeck(
            name: "\(course.title) (\(filterTarget.rawValue))",
            cards: cachedTargetCards
        )
        activeStudyDeck = studyDeck
    }
    
    // NEW-05: 複数カード成果をメモリ上で一括適用し、保存処理を1回のみに集約
    private func updateCardsInCourseBulk(_ updatedCards: [AnkiCard]) {
        var updatedCourse = course
        var didModify = false
        
        for updatedCard in updatedCards {
            for dIdx in updatedCourse.decks.indices {
                if let cIdx = updatedCourse.decks[dIdx].cards.firstIndex(where: { $0.id == updatedCard.id }) {
                    updatedCourse.decks[dIdx].cards[cIdx] = updatedCard
                    didModify = true
                    break
                }
            }
        }
        
        if didModify {
            updatedCourse.updatedAt = Date()
            self.course = updatedCourse
            recalculateFilteredCards()
            onSaveCourse(updatedCourse)
        }
    }
    
    // ARC-02 安全なカードピンポイント更新
    private func updateSingleCardInCourse(_ updatedCard: AnkiCard) {
        var updatedCourse = course
        var updated = false
        
        for dIdx in updatedCourse.decks.indices {
            if let cIdx = updatedCourse.decks[dIdx].cards.firstIndex(where: { $0.id == updatedCard.id }) {
                updatedCourse.decks[dIdx].cards[cIdx] = updatedCard
                updated = true
                break
            }
        }
        
        if !updated {
            if updatedCourse.decks.isEmpty {
                updatedCourse.decks = [AnkiDeck(name: "メイン単語帳", cards: [updatedCard])]
            } else {
                updatedCourse.decks[0].cards.append(updatedCard)
            }
        }
        
        updatedCourse.updatedAt = Date()
        self.course = updatedCourse
        recalculateFilteredCards()
        onSaveCourse(updatedCourse)
    }
    
    private func updateAllCards(_ updatedCards: [AnkiCard]) {
        var updatedCourse = course
        if updatedCourse.decks.isEmpty {
            updatedCourse.decks = [AnkiDeck(name: "メイン単語帳", cards: updatedCards)]
        } else {
            updatedCourse.decks[0].cards = updatedCards
        }
        updatedCourse.updatedAt = Date()
        self.course = updatedCourse
        recalculateFilteredCards()
        onSaveCourse(updatedCourse)
    }
    
    // カード削除
    private func deleteCardFromCourse(_ cardId: UUID) {
        var updatedCourse = course
        for dIdx in updatedCourse.decks.indices {
            updatedCourse.decks[dIdx].cards.removeAll { $0.id == cardId }
        }
        updatedCourse.updatedAt = Date()
        self.course = updatedCourse
        recalculateFilteredCards()
        onSaveCourse(updatedCourse)
    }
    
    // 新規カードの追加
    private func addCardsToCourse(_ newCards: [AnkiCard]) {
        var updatedCourse = course
        if updatedCourse.decks.isEmpty {
            updatedCourse.decks = [AnkiDeck(name: "メイン単語帳", cards: newCards)]
        } else {
            updatedCourse.decks[0].cards.append(contentsOf: newCards)
        }
        updatedCourse.updatedAt = Date()
        self.course = updatedCourse
        recalculateFilteredCards()
        onSaveCourse(updatedCourse)
    }
}
