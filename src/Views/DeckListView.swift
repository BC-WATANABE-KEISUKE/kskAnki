import SwiftUI

/// アプリメイン・全フォルダ＆コース＆マイ単語帳一覧画面 (ARC-01, ARC-08 MainActor適合, PERF-02 キャッシュ最適化)
@available(iOS 17.0, macOS 14.0, *)
public struct DeckListView: View {
    @Bindable public var store: DeckStore
    
    // UI状態管理
    @State private var selectedFolderId: UUID? = nil
    @State private var selectedCourseForDetail: Course? = nil
    @State private var selectedDeckForStudy: AnkiDeck? = nil
    
    // モーダルシート管理
    @State private var isSettingsPresented: Bool = false
    @State private var isStatsPresented: Bool = false
    @State private var isCreateFolderPresented: Bool = false
    @State private var isCreateCoursePresented: Bool = false
    
    public init(store: DeckStore) {
        self.store = store
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. トップ概要ステータスカード (ストリーク日数 & 本日目標進捗)
                topStatusHeader
                
                // 2. フォルダ切替チップフィルター (すべて / 各フォルダ)
                folderChipsScrollView
                
                // 3. コース＆マイ単語帳一覧リスト
                courseAndDeckList
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("kskAnki")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 12) {
                        Button(action: { isStatsPresented = true }) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.title3)
                        }
                        
                        Button(action: { isSettingsPresented = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                        }
                    }
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView(store: store)
            }
            .sheet(isPresented: $isStatsPresented) {
                StudyStatsView(store: store)
            }
            .sheet(isPresented: $isCreateFolderPresented) {
                CreateFolderView { newFolder in
                    store.addFolder(newFolder)
                    selectedFolderId = newFolder.id
                }
            }
            .sheet(isPresented: $isCreateCoursePresented) {
                CreateCourseView(folders: store.folders) { newCourse in
                    store.addCourse(newCourse)
                    selectedCourseForDetail = newCourse
                }
            }
            .sheet(item: $selectedCourseForDetail) { course in
                if let latestCourse = store.courses.first(where: { $0.id == course.id }) {
                    CourseDetailView(
                        course: latestCourse,
                        onRecordRating: { cardId, rating in
                            store.recordStudy(cardId: cardId, rating: rating)
                        },
                        onSaveCourse: { updatedCourse in
                            store.updateCourse(updatedCourse)
                        }
                    )
                }
            }
            #if os(iOS)
            .fullScreenCover(item: $selectedDeckForStudy) { deck in
                CardStudyView(
                    deck: deck,
                    onRecordRating: { cardId, rating in
                        store.recordStudy(cardId: cardId, rating: rating)
                    },
                    onFinishSession: { sessionCards, ratings, shouldSave in
                        guard shouldSave else { return }
                        store.updateCardsInDeckBulk(sessionCards, inDeckId: deck.id)
                    }
                )
            }
            #else
            .sheet(item: $selectedDeckForStudy) { deck in
                CardStudyView(
                    deck: deck,
                    onRecordRating: { cardId, rating in
                        store.recordStudy(cardId: cardId, rating: rating)
                    },
                    onFinishSession: { sessionCards, ratings, shouldSave in
                        guard shouldSave else { return }
                        store.updateCardsInDeckBulk(sessionCards, inDeckId: deck.id)
                    }
                )
            }
            #endif
        }
    }
    
    // トップヘッダーサマリー
    private var topStatusHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("\(store.streakDaysCount)日連続学習中！")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                
                let todayCount = store.todayStudiedCardsCount
                Text("本日: \(todayCount) / \(store.dailyGoalCardsCount) 枚完了")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            ProgressView(value: min(1.0, Double(store.todayStudiedCardsCount) / Double(max(1, store.dailyGoalCardsCount))))
                .progressViewStyle(.circular)
                .tint(.orange)
        }
        .padding(16)
        .background(cardBgColor)
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // フォルダフィルターチップ
    private var folderChipsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(title: "すべて", isSelected: selectedFolderId == nil) {
                    selectedFolderId = nil
                }
                
                ForEach(store.folders) { folder in
                    chipButton(title: folder.name, isSelected: selectedFolderId == folder.id) {
                        selectedFolderId = folder.id
                    }
                }
                
                Button(action: { isCreateFolderPresented = true }) {
                    Image(systemName: "folder.badge.plus")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    private func chipButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote)
                .fontWeight(isSelected ? .bold : .medium)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.15))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
    
    // コース＆マイ単語帳一覧
    private var courseAndDeckList: some View {
        List {
            Section {
                HStack {
                    Text("コース一覧")
                        .font(.title3)
                        .fontWeight(.bold)
                    Spacer()
                    Button(action: { isCreateCoursePresented = true }) {
                        Label("新規コース", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
                .listRowBackground(Color.clear)
                
                let filteredCourses = selectedFolderId == nil ? store.courses : store.courses.filter { $0.folderId == selectedFolderId }
                
                if filteredCourses.isEmpty {
                    ContentUnavailableView(
                        "コースが登録されていません",
                        systemImage: "book.closed",
                        description: Text("「新規コース」ボタンから新しいコースを作成してください。")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    // PERF-01: LazyVStack 最適化
                    LazyVStack(spacing: 12) {
                        ForEach(filteredCourses) { course in
                            courseCardRow(course)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
    }
    
    private func courseCardRow(_ course: Course) -> some View {
        Button(action: {
            selectedCourseForDetail = course
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(course.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if !course.description.isEmpty {
                    Text(course.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                let cardCount = course.decks.reduce(0) { $0 + $1.cards.count }
                HStack(spacing: 16) {
                    Label("\(cardCount) 枚", systemImage: "rectangle.stack")
                    Label("\(course.decks.count) デッキ", systemImage: "folder")
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(16)
            .background(cardBgColor)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
    
    private var backgroundColor: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color.gray.opacity(0.06)
        #endif
    }
    
    private var cardBgColor: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color.white
        #endif
    }
}

// Xcode SwiftUI Canvas プレビュー定義 (Xcode 内でのリアルタイム表示用)
@available(iOS 17.0, macOS 14.0, *)
struct DeckListView_Previews: PreviewProvider {
    static var previews: some View {
        DeckListView(store: DeckStore())
    }
}
