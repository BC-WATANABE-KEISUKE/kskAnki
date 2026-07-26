import SwiftUI

/// トップ画面：コース＆フォルダ＆単語帳選択・新規コース作成・アーカイブ・ソート・ページネーション・設定遷移
@available(iOS 17.0, macOS 14.0, *)
public struct DeckListView: View {
    @Bindable public var store: DeckStore
    @State private var selectedDeckForStudy: AnkiDeck?
    @State private var selectedCourseForDetail: Course?
    @State private var isSettingsPresented: Bool = false
    @State private var isStatsPresented: Bool = false
    @State private var isCreateFolderPresented: Bool = false
    @State private var isCreateCoursePresented: Bool = false
    
    // アーカイブ表示切替ステート (false: アクティブ, true: アーカイブ済み)
    @State private var showArchivedCourses: Bool = false
    
    // フォルダフィルターステート (nil = すべて, UUID.nil = 未分類, 特定UUID = 各フォルダ)
    @State private var selectedFolderId: UUID? = nil
    
    // ソート & ページネーション用ステート
    @State private var selectedSortOption: CourseSortOption = .lastStudied
    @State private var currentPage: Int = 1
    private let pageSize: Int = 3
    
    public init(store: DeckStore) {
        self.store = store
    }
    
    // フォルダ & アーカイブフィルター適用後のコース一覧
    private var filteredCourses: [Course] {
        store.courses.filter { course in
            let matchesFolder = (selectedFolderId == nil) || (course.folderId == selectedFolderId)
            let matchesArchive = course.isArchived == showArchivedCourses
            return matchesFolder && matchesArchive
        }
    }
    
    // ソート済みコース一覧の計算
    private var sortedCourses: [Course] {
        switch selectedSortOption {
        case .nameAsc:
            return filteredCourses.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .lastStudied:
            return filteredCourses.sorted {
                ($0.lastStudiedAt ?? Date.distantPast) > ($1.lastStudiedAt ?? Date.distantPast)
            }
        case .updatedAt:
            return filteredCourses.sorted { $0.updatedAt > $1.updatedAt }
        }
    }
    
    // 総ページ数
    private var totalPages: Int {
        max(1, Int(ceil(Double(sortedCourses.count) / Double(pageSize))))
    }
    
    // 現在のページに表示するコース一覧
    private var pagedCourses: [Course] {
        let startIndex = (currentPage - 1) * pageSize
        guard startIndex < sortedCourses.count else { return [] }
        let endIndex = min(startIndex + pageSize, sortedCourses.count)
        return Array(sortedCourses[startIndex..<endIndex])
    }
    
    public var body: some View {
        NavigationStack {
            mainList
                .navigationTitle("kskAnki")
                .toolbar {
                    // 左側：設定 ＆ 統計分析ボタン
                    ToolbarItem(placement: .cancellationAction) {
                        HStack(spacing: 12) {
                            Button(action: {
                                isSettingsPresented = true
                            }) {
                                Image(systemName: "gearshape.fill")
                                    .foregroundColor(.primary)
                            }
                            .accessibilityLabel("設定")
                            
                            Button(action: {
                                isStatsPresented = true
                            }) {
                                Image(systemName: "chart.bar.xaxis")
                                    .foregroundColor(.blue)
                            }
                            .accessibilityLabel("学習統計分析ダッシュボード")
                        }
                    }
                    
                    // 右側：コース追加 / フォルダ追加メニュー
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(action: {
                                isCreateCoursePresented = true
                            }) {
                                Label("新規コースを作成", systemImage: "rectangle.stack.badge.plus")
                            }
                            
                            Button(action: {
                                isCreateFolderPresented = true
                            }) {
                                Label("新規フォルダを作成", systemImage: "folder.badge.plus")
                            }
                        } label: {
                            Image(systemName: "plus")
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
                        // NEW-05: 保存処理を1回のみに集約する一括更新呼び出し
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
                        // NEW-05: 保存処理を1回のみに集約する一括更新呼び出し
                        store.updateCardsInDeckBulk(sessionCards, inDeckId: deck.id)
                    }
                )
            }
            #endif
        }
    }
    
    @ViewBuilder
    private var mainList: some View {
        #if os(iOS)
        List {
            // 0. 学習ストリーク & 本日の目標進捗セクション
            Section {
                HStack(spacing: 16) {
                    // ストリークバッジ
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("🔥")
                                .font(.title2)
                            Text("\(store.streakDaysCount)日連続学習中！")
                                .font(.subheadline)
                                .fontWeight(.black)
                                .foregroundColor(.orange)
                        }
                        Text("継続は力なり。毎日暗記で記憶定着！")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // 日次目標達成メーター
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("本日の目標")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("\(store.todayStudiedCardsCount) / \(store.dailyGoalCardsCount) 枚")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        
                        ProgressView(value: Double(store.todayStudiedCardsCount), total: Double(store.dailyGoalCardsCount))
                            .frame(width: 90)
                            .tint(.blue)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // 1. フォルダ選択 & コース表示セクション
            Section {
                VStack(spacing: 14) {
                    // フォルダフィルターチップバー
                    folderChipsHeader
                    
                    // ソート & ページネーション & アーカイブ切替バー
                    courseControlHeader
                    
                    // コースカード一覧
                    if pagedCourses.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: showArchivedCourses ? "archivebox" : "rectangle.stack")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text(showArchivedCourses ? "アーカイブ済みのコースはありません" : "該当するコースがありません")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(pagedCourses) { course in
                                    courseCard(course)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            } header: {
                HStack {
                    Text(showArchivedCourses ? "アーカイブ済みコース" : "学習コースを選択")
                        .font(.headline)
                    Spacer()
                    // アーカイブ表示トグルボタン
                    Button(action: {
                        withAnimation {
                            showArchivedCourses.toggle()
                            currentPage = 1
                        }
                    }) {
                        Label(
                            showArchivedCourses ? "アクティブコースへ" : "アーカイブ表示",
                            systemImage: showArchivedCourses ? "tray.full.fill" : "archivebox"
                        )
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // 2. 個別単語帳セクション
            Section {
                ForEach(store.allDecks) { deck in
                    deckRow(deck)
                }
            } header: {
                Text("マイ単語帳 (すべてのデッキ)")
                    .font(.headline)
            }
        }
        .listStyle(.insetGrouped)
        #else
        List {
            Section("学習コース") {
                ForEach(sortedCourses) { course in
                    VStack(alignment: .leading) {
                        Text(course.title).font(.headline)
                        Text(course.description).font(.subheadline)
                    }
                }
            }
            Section("マイ単語帳") {
                ForEach(store.allDecks) { deck in
                    deckRow(deck)
                }
            }
        }
        #endif
    }
    
    // フォルダ切り替えチップヘッダー
    private var folderChipsHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // すべて
                folderChip(title: "すべて", icon: "square.grid.2x2.fill", isSelected: selectedFolderId == nil) {
                    selectedFolderId = nil
                    currentPage = 1
                }
                
                // 各フォルダ
                ForEach(store.folders) { folder in
                    folderChip(
                        title: folder.name,
                        icon: folder.iconName,
                        isSelected: selectedFolderId == folder.id
                    ) {
                        selectedFolderId = folder.id
                        currentPage = 1
                    }
                }
                
                // ＋ 新規フォルダ作成ボタン
                Button(action: {
                    isCreateFolderPresented = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("フォルダ作成")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.12))
                    .foregroundColor(.primary)
                    .cornerRadius(16)
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    private func folderChip(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isSelected ? Color.blue : Color.gray.opacity(0.12))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
    
    // コース並べ替え・ページネーションコントロールバー
    private var courseControlHeader: some View {
        HStack {
            // 並べ替え Menu
            Menu {
                Picker("並べ替え", selection: $selectedSortOption) {
                    ForEach(CourseSortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                    Text(selectedSortOption.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(8)
            }
            .onChange(of: selectedSortOption) {
                currentPage = 1
            }
            
            Spacer()
            
            // ページネーションコントロール
            HStack(spacing: 8) {
                Button(action: {
                    if currentPage > 1 {
                        withAnimation { currentPage -= 1 }
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                        .foregroundColor(currentPage > 1 ? .blue : .gray.opacity(0.4))
                }
                .disabled(currentPage <= 1)
                
                Text("\(currentPage) / \(totalPages)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                Button(action: {
                    if currentPage < totalPages {
                        withAnimation { currentPage += 1 }
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(currentPage < totalPages ? .blue : .gray.opacity(0.4))
                }
                .disabled(currentPage >= totalPages)
            }
        }
        .padding(.horizontal, 4)
    }
    
    // コースカードコンポーネント (コンテキストメニューでアーカイブ・削除操作対応)
    private func courseCard(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: course.iconName)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.blue)
                    .cornerRadius(12)
                Spacer()
                Text("\(course.totalCardsCount)枚")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(course.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Text(course.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button(action: {
                selectedCourseForDetail = course
            }) {
                Text("コース詳細 / 学習")
                    .font(.caption)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 240, height: 190)
        .background(cardBgColor)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .onTapGesture {
            selectedCourseForDetail = course
        }
        .contextMenu {
            Button(action: {
                store.toggleArchiveCourse(course.id)
            }) {
                Label(
                    course.isArchived ? "アーカイブから復元" : "アーカイブする",
                    systemImage: course.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
            }
            
            Button(role: .destructive, action: {
                store.deleteCourse(course.id)
            }) {
                Label("コースを削除", systemImage: "trash")
            }
        }
    }
    
    private func deckRow(_ deck: AnkiDeck) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(deck.name)
                    .font(.headline)
                if !deck.description.isEmpty {
                    Text(deck.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 12) {
                    Label("\(deck.cards.count) 枚", systemImage: "rectangle.stack")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(action: {
                selectedDeckForStudy = deck
            }) {
                Text("学習")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(20)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private var cardBgColor: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }
}
