import SwiftUI
import PhotosUI

/// カードの編集モーダル (表面3タイプ選択 & 画像独立セクション & PhotosPicker アルバム選択対応)
@available(iOS 17.0, macOS 14.0, *)
public struct EditCardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var frontType: CardFrontType
    @State private var frontText: String
    @State private var backText: String
    @State private var japaneseTranslation: String
    @State private var exampleSentence: String
    @State private var exampleTranslation: String
    @State private var synonyms: String
    @State private var antonyms: String
    @State private var explanation1: String
    @State private var explanation2: String
    @State private var explanation3: String
    
    // 画像関連ステート (独立セクション)
    @State private var frontImageURLs: [String]
    @State private var backImageURLs: [String]
    @State private var frontImagesInput: String
    @State private var backImagesInput: String
    
    @State private var mainCategory: String
    @State private var subCategory: String
    @State private var tagInput: String
    @State private var userNotes: String
    @State private var speechLanguage: String
    @State private var isFavorite: Bool
    
    // PhotosPicker 選択アイテム
    @State private var selectedFrontPhotoItems: [PhotosPickerItem] = []
    @State private var selectedBackPhotoItems: [PhotosPickerItem] = []
    
    public let card: AnkiCard
    public let onSave: (AnkiCard) -> Void
    
    public init(card: AnkiCard, onSave: @escaping (AnkiCard) -> Void) {
        self.card = card
        self.onSave = onSave
        self._frontType = State(initialValue: card.frontType)
        self._frontText = State(initialValue: card.frontText)
        self._backText = State(initialValue: card.backText)
        self._japaneseTranslation = State(initialValue: card.japaneseTranslation)
        self._exampleSentence = State(initialValue: card.exampleSentence)
        self._exampleTranslation = State(initialValue: card.exampleTranslation)
        self._synonyms = State(initialValue: card.synonyms)
        self._antonyms = State(initialValue: card.antonyms)
        self._explanation1 = State(initialValue: card.explanation1)
        self._explanation2 = State(initialValue: card.explanation2)
        self._explanation3 = State(initialValue: card.explanation3)
        self._frontImageURLs = State(initialValue: card.frontImageURLs)
        self._backImageURLs = State(initialValue: card.backImageURLs)
        self._frontImagesInput = State(initialValue: card.frontImageURLs.joined(separator: ", "))
        self._backImagesInput = State(initialValue: card.backImageURLs.joined(separator: ", "))
        self._mainCategory = State(initialValue: card.mainCategory)
        self._subCategory = State(initialValue: card.subCategory)
        self._speechLanguage = State(initialValue: card.speechLanguage ?? "en-US")
        self._tagInput = State(initialValue: card.tags.joined(separator: ", "))
        self._userNotes = State(initialValue: card.userNotes)
        self._isFavorite = State(initialValue: card.isFavorite)
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("表面のパターン (表示スタイル)") {
                    Picker("表面パターン", selection: $frontType) {
                        ForEach(CardFrontType.allCases) { type in
                            Label(type.rawValue, systemImage: type.iconName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if frontType == .cloze {
                        Text("💡 穴埋め設定ヒント: 文章内の隠したいキーワードを {{英単語}} または [英単語] で囲むと自動でマスク伏せ字になります。")
                            .font(.caption)
                            .foregroundColor(.purple)
                    } else if frontType == .word {
                        Text("💡 単語スタイル: 英単語やフレーズを画面中央に強調して大きく表示します。")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Section("表面 (Question / Front)") {
                    TextField("問題・表側のテキストを入力", text: $frontText, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("裏面 (Answer / Back)") {
                    TextField("解答・裏側のテキスト", text: $backText, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("日本語訳 / 和訳", text: $japaneseTranslation)
                }
                
                // 別枠 1: 📷 表面の画像独立セクション
                Section("📷 表面の画像 (Question Images)") {
                    TextField("画像Web URL (カンマ区切り)", text: $frontImagesInput)
                    
                    PhotosPicker(selection: $selectedFrontPhotoItems, maxSelectionCount: 5, matching: .images) {
                        Label("フォトライブラリから画像を選択", systemImage: "photo.badge.plus")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                    
                    if !frontImageURLs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("登録中の表面画像 (\(frontImageURLs.count)枚):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(frontImageURLs, id: \.self) { url in
                                HStack {
                                    Image(systemName: "photo")
                                        .foregroundColor(.blue)
                                    Text(url)
                                        .font(.caption2)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(action: {
                                        frontImageURLs.removeAll { $0 == url }
                                        frontImagesInput = frontImageURLs.joined(separator: ", ")
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                
                // 別枠 2: 📷 裏面の画像独立セクション
                Section("📷 裏面の画像 (Answer Images)") {
                    TextField("画像Web URL (カンマ区切り)", text: $backImagesInput)
                    
                    PhotosPicker(selection: $selectedBackPhotoItems, maxSelectionCount: 5, matching: .images) {
                        Label("フォトライブラリから画像を選択", systemImage: "photo.badge.plus")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                    
                    if !backImageURLs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("登録中の裏面画像 (\(backImageURLs.count)枚):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(backImageURLs, id: \.self) { url in
                                HStack {
                                    Image(systemName: "photo")
                                        .foregroundColor(.orange)
                                    Text(url)
                                        .font(.caption2)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(action: {
                                        backImageURLs.removeAll { $0 == url }
                                        backImagesInput = backImageURLs.joined(separator: ", ")
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                
                Section("例文 & 語彙") {
                    TextField("例文", text: $exampleSentence, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("例文の和訳", text: $exampleTranslation, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("類義語 (Synonyms)", text: $synonyms)
                    TextField("反対語 (Antonyms)", text: $antonyms)
                }
                
                Section("詳細解説 (設定時のみ表示)") {
                    TextField("解説 1", text: $explanation1, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("解説 2", text: $explanation2, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("解説 3", text: $explanation3, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                Section("カテゴリー設定") {
                    TextField("メインカテゴリー (例: 英語, IT)", text: $mainCategory)
                    TextField("サブカテゴリー (例: 単語, OS)", text: $subCategory)
                }
                
                Section("音声読み上げ言語 (TTS)") {
                    Picker("読み上げ言語", selection: $speechLanguage) {
                        Text("英語 (en-US)").tag("en-US")
                        Text("日本語 (ja-JP)").tag("ja-JP")
                        Text("スペイン語 (es-ES)").tag("es-ES")
                    }
                }
                
                Section("マイメモ (My Notes)") {
                    TextField("個人用メモ・解説・補足など", text: $userNotes, axis: .vertical)
                        .lineLimit(2...5)
                }
                
                Section("タグ & お気に入り") {
                    TextField("タグ (カンマ区切り)", text: $tagInput)
                    Toggle("★ お気に入りに登録", isOn: $isFavorite)
                }
            }
            .onChange(of: selectedFrontPhotoItems) { _, items in
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            if let path = try? ImageStore.saveImage(data: data) {
                                frontImageURLs.append(path)
                            }
                        }
                    }
                    selectedFrontPhotoItems = []
                }
            }
            .onChange(of: selectedBackPhotoItems) { _, items in
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            if let path = try? ImageStore.saveImage(data: data) {
                                backImageURLs.append(path)
                            }
                        }
                    }
                    selectedBackPhotoItems = []
                }
            }
            .navigationTitle("カードを編集")
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
                    Button("保存") {
                        var updated = card
                        updated.frontType = frontType
                        updated.frontText = frontText.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.backText = backText.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.japaneseTranslation = japaneseTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.exampleSentence = exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.exampleTranslation = exampleTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.synonyms = synonyms.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.antonyms = antonyms.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.explanation1 = explanation1.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.explanation2 = explanation2.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.explanation3 = explanation3.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        let textFrontImgs = frontImagesInput
                            .components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        let textBackImgs = backImagesInput
                            .components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        
                        updated.frontImageURLs = Array(Set(frontImageURLs + textFrontImgs))
                        updated.backImageURLs = Array(Set(backImageURLs + textBackImgs))
                        
                        updated.mainCategory = mainCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.subCategory = subCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.speechLanguage = speechLanguage
                        updated.userNotes = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.isFavorite = isFavorite
                        updated.tags = tagInput
                            .components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(frontText.isEmpty || backText.isEmpty)
                }
            }
        }
    }
}
