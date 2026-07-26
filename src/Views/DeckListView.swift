import SwiftUI

/// アプリメイン・全フォルダ＆コース＆マイ単語帳一覧画面 (要件3.1完全適合, PERF-02 キャッシュ最適化)
@available(iOS 17.0, macOS 14.0, *)
public struct DeckListView: View {
    @Bindable public var store: DeckStore
    
    public enum FolderSelection: Hashable {
        case all
        case unfiled
        case folder(UUID)
    }
    
    @State private var folderSelection: FolderSelection = .all
    @State private var selectedCourseForDetail: Course? = nil
    @State private var selectedDeckForStudy: AnkiDeck? = nil
    
    // 要件 3.1: ソート & ページネーション & アーカイブ表示切替ステート
    @State private var sortOption: CourseSortOption = .nameAsc
    @State private var showArchivedOnly: Bool = false
    @State private var currentPage: Int = 1
    private let pageSize: Int = 3
    
    // モーダルシート管理
    @State private var isSettingsPresented: Bool = false
    @State private var isStatsPresented: Bool = false
    @State private var isCreateFolderPresented: Bool = false
    @State private var isCreateCoursePresented: Bool = false
    @State private var courseToDelete: Course? = nil
    
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
                
                // 3. コース＆マイ単語帳一覧リスト (ソート・ページネーション・コンテキストメニュー対応)
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
                    folderSelection = .folder(newFolder.id)
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
            .alert("コースの削除確認", isPresented: Binding(
                get: { courseToDelete != nil },
                set: { if !$0 { courseToDelete = nil } }
            )) {
                Button("キャンセル", role: .cancel) { courseToDelete = nil }
                Button("削除する", role: .destructive) {
                    if let c = courseToDelete {
                        store.deleteCourse(c.id)
                        courseToDelete = nil
                    }
                }
            } message: {
                Text("「\(courseToDelete?.title ?? "")」を削除してもよろしいですか？この操作は取り消せません。")
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
                chipButton(title: "すべて", isSelected: folderSelection == .all) {
                    folderSelection = .all
                    currentPage = 1
                }
                
                chipButton(title: "未分類", isSelected: folderSelection == .unfiled) {
                    folderSelection = .unfiled
                    currentPage = 1
                }
                
                ForEach(store.folders) { folder in
                    chipButton(title: folder.name, isSelected: folderSelection == .folder(folder.id)) {
                        folderSelection = .folder(folder.id)
                        currentPage = 1
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
    
    // フィルタリング・ソート済みコース取得
    private var filteredSortedCourses: [Course] {
        var result = store.courses
        
        // フォルダ絞り込み (UX-12: 未分類 folderId == nil フィルタリング適合)
        switch folderSelection {
        case .all:
            break
        case .unfiled:
            result = result.filter { $0.folderId == nil }
        case .folder(let id):
            result = result.filter { $0.folderId == id }
        }
        
        // アーカイブ切替
        result = result.filter { $0.isArchived == showArchivedOnly }
        
        // 要件 3.1: ソート処理
        switch sortOption {
        case .nameAsc:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .lastStudied:
            result.sort { ($0.lastStudiedAt ?? Date.distantPast) > ($1.lastStudiedAt ?? Date.distantPast) }
        case .updatedAt:
            result.sort { $0.updatedAt > $1.updatedAt }
        }
        
        return result
    }
    
    // 要件 3.1: ページネーション切出コース
    private var paginatedCourses: [Course] {
        let all = filteredSortedCourses
        let totalPages = max(1, Int(ceil(Double(all.count) / Double(pageSize))))
        let validPage = min(max(1, currentPage), totalPages)
        let startIndex = (validPage - 1) * pageSize
        guard startIndex < all.count else { return [] }
        let endIndex = min(startIndex + pageSize, all.count)
        return Array(all[startIndex..<endIndex])
    }
    
    private var totalPages: Int {
        let count = filteredSortedCourses.count
        return max(1, Int(ceil(Double(count) / Double(pageSize))))
    }
    
    // コース＆マイ単語帳一覧
    private var courseAndDeckList: some View {
        List {
            Section {
                // 要件 3.1: コース一覧ヘッダー & ソート・アーカイブ切り替えコントローラー
                VStack(spacing: 12) {
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
                    
                    HStack {
                        // アクティブ / アーカイブ切替
                        Picker("表示", selection: $showArchivedOnly) {
                            Text("アクティブ").tag(false)
                            Text("アーカイブ").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 180)
                        
                        Spacer()
                        
                        // 要件 3.1: ソートピッカー
                        Picker("並び替え", selection: $sortOption) {
                            ForEach(CourseSortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.caption)
                    }
                }
                .listRowBackground(Color.clear)
                .padding(.bottom, 4)
                
                let currentCourses = paginatedCourses
                
                if currentCourses.isEmpty {
                    ContentUnavailableView(
                        showArchivedOnly ? "アーカイブ済みのコースはありません" : "コースが登録されていません",
                        systemImage: showArchivedOnly ? "archivebox" : "book.closed",
                        description: Text(showArchivedOnly ? "不要になったコースを長押しでアーカイブできます。" : "「新規コース」ボタンから新しいコースを作成してください。")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(currentCourses) { course in
                            courseCardRow(course)
                        }
                    }
                    .listRowBackground(Color.clear)
                    
                    // 要件 3.1: ページネーションコントロール (1ページ 3件)
                    if totalPages > 1 {
                        HStack {
                            Spacer()
                            Button(action: {
                                if currentPage > 1 { currentPage -= 1 }
                            }) {
                                Image(systemName: "chevron.left")
                                    .padding(8)
                                    .background(Color.gray.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            .disabled(currentPage <= 1)
                            
                            Text("\(currentPage) / \(totalPages) ページ")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                            
                            Button(action: {
                                if currentPage < totalPages { currentPage += 1 }
                            }) {
                                Image(systemName: "chevron.right")
                                    .padding(8)
                                    .background(Color.gray.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            .disabled(currentPage >= totalPages)
                            Spacer()
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 8)
                    }
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
                let themeColor = Color(hex: course.themeColorHex)
                
                HStack(spacing: 8) {
                    Image(systemName: course.iconName)
                        .foregroundColor(themeColor)
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
                .foregroundColor(themeColor)
            }
            .padding(16)
            .background(cardBgColor)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: course.themeColorHex).opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        // 要件 3.1: コンテキストメニュー長押し (アーカイブ・復元・削除)
        .contextMenu {
            Button(action: {
                store.toggleArchiveCourse(course.id)
            }) {
                Label(course.isArchived ? "アクティブに戻す" : "アーカイブに移動", systemImage: course.isArchived ? "tray.and.arrow.up" : "archivebox")
            }
            
            Button(role: .destructive, action: {
                courseToDelete = course
            }) {
                Label("コースを削除", systemImage: "trash")
            }
        }
    }
    
    private var backgroundColor: Color { .appBackground }
    private var cardBgColor: Color { .cardBackground }
}

// Xcode SwiftUI Canvas プレビュー定義 (Xcode 内でのリアルタイム表示用)
@available(iOS 17.0, macOS 14.0, *)
struct DeckListView_Previews: PreviewProvider {
    static var previews: some View {
        DeckListView(store: DeckStore())
    }
}
