import SwiftUI

/// 新規コース作成シートモーダル
@available(iOS 17.0, macOS 14.0, *)
public struct CreateCourseView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var selectedIcon: String = "book.fill"
    @State private var selectedColorHex: String = "#007AFF"
    @State private var selectedFolderId: UUID? = nil
    
    public let folders: [CourseFolder]
    public let onCreateCourse: (Course) -> Void
    
    // アプリで選べるアイコン一覧
    private let availableIcons = [
        "book.fill", "globe.americas.fill", "cpu.fill", "atom", "hourglass",
        "star.fill", "lightbulb.fill", "heart.fill", "graduationcap.fill",
        "brain.head.profile", "bubble.left.and.bubble.right.fill", "music.note"
    ]
    
    // テーマカラー選択肢
    private let availableColors = [
        "#007AFF", "#FF9500", "#FF3B30", "#34C759", "#AF52DE", "#5856D6", "#FF2D55"
    ]
    
    public init(folders: [CourseFolder], onCreateCourse: @escaping (Course) -> Void) {
        self.folders = folders
        self.onCreateCourse = onCreateCourse
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("コース基本情報") {
                    TextField("コースタイトル (例: 英会話・TOEIC 800点)", text: $title)
                    TextField("説明・概要 (例: スコア直結の必須単語集)", text: $description)
                }
                
                Section("アイコンの選択") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title2)
                                .foregroundColor(selectedIcon == icon ? .white : .primary)
                                .frame(width: 44, height: 44)
                                .background(selectedIcon == icon ? Color.blue : Color.gray.opacity(0.12))
                                .cornerRadius(10)
                                .onTapGesture {
                                    selectedIcon = icon
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("所属フォルダ") {
                    Picker("フォルダを選択", selection: $selectedFolderId) {
                        Text("未分類 (フォルダなし)").tag(UUID?.none)
                        ForEach(folders) { folder in
                            Text(folder.name).tag(UUID?.some(folder.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("新しいコースを作成")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") {
                        let newCourse = Course(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                            iconName: selectedIcon,
                            themeColorHex: selectedColorHex,
                            decks: [AnkiDeck(name: "メイン単語帳", cards: [])],
                            folderId: selectedFolderId
                        )
                        onCreateCourse(newCourse)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
