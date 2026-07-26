import SwiftUI
import PhotosUI

/// カード追加モーダル (表面3タイプ選択 & 画像独立セクション & PhotosPicker アルバム選択対応)
@available(iOS 17.0, macOS 14.0, *)
public struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int = 0 // 0: 手動追加, 1: CSV取り込み
    
    // 手動フォーム用ステート
    @State private var frontType: CardFrontType = .question
    @State private var frontText: String = ""
    @State private var backText: String = ""
    @State private var japaneseTranslation: String = ""
    @State private var exampleSentence: String = ""
    @State private var exampleTranslation: String = ""
    @State private var synonyms: String = ""
    @State private var antonyms: String = ""
    @State private var explanation1: String = ""
    @State private var explanation2: String = ""
    @State private var explanation3: String = ""
    
    // 画像関連ステート (独立セクション)
    @State private var frontImageURLs: [String] = []
    @State private var backImageURLs: [String] = []
    @State private var frontImagesInput: String = ""
    @State private var backImagesInput: String = ""
    
    @State private var mainCategory: String = ""
    @State private var subCategory: String = ""
    @State private var tagInput: String = ""
    @State private var isFavorite: Bool = false
    
    // PhotosPicker 選択アイテム
    @State private var selectedFrontPhotoItems: [PhotosPickerItem] = []
    @State private var selectedBackPhotoItems: [PhotosPickerItem] = []
    
    // CSV用ステート
    @State private var csvText: String = ""
    @State private var importedCountMessage: String?
    
    public let onAddCards: ([AnkiCard]) -> Void
    
    public init(onAddCards: @escaping ([AnkiCard]) -> Void) {
        self.onAddCards = onAddCards
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("追加方法", selection: $selectedTab) {
                    Text("1枚ずつ手動追加").tag(0)
                    Text("CSV取り込み").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedTab == 0 {
                    manualAddForm
                } else {
                    csvImportForm
                }
            }
            .navigationTitle("カードを追加")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // 手動追加フォーム
    private var manualAddForm: some View {
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
                TextField("解答テキストを入力", text: $backText, axis: .vertical)
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
                        Text("登録予定の表面画像 (\(frontImageURLs.count)枚):")
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
                        Text("登録予定の裏面画像 (\(backImageURLs.count)枚):")
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
            
            Section("詳細解説 (任意)") {
                TextField("解説 1", text: $explanation1, axis: .vertical)
                    .lineLimit(2...4)
                TextField("解説 2", text: $explanation2, axis: .vertical)
                    .lineLimit(2...4)
                TextField("解説 3", text: $explanation3, axis: .vertical)
                    .lineLimit(2...4)
            }
            
            Section("カテゴリー設定") {
                TextField("メインカテゴリー (例: 英単語, IT基礎)", text: $mainCategory)
                TextField("サブカテゴリー (例: 動詞, ネットワーク)", text: $subCategory)
            }
            
            Section("属性") {
                TextField("タグ (カンマ区切り)", text: $tagInput)
                Toggle("お気に入りに追加", isOn: $isFavorite)
            }
            
            Section {
                Button(action: saveSingleCard) {
                    Text("カードを追加")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                }
                .listRowBackground(Color.blue)
                .disabled(frontText.isEmpty || backText.isEmpty)
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
    }
    
    // CSVインポートフォーム
    private var csvImportForm: some View {
        Form {
            Section {
                Text("カンマ(,)区切りのCSVフォーマット:\n表面, 裏面, メインカテゴリー, サブカテゴリー, タグ")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $csvText)
                    .frame(minHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            } header: {
                Text("CSVテキストの貼り付け")
            } footer: {
                Text("例:\nApple, りんご, 英語, 名詞, 基礎\nDeadlock, デッドロック, IT, OS, 重要")
            }
            
            if let msg = importedCountMessage {
                Section {
                    Text(msg)
                        .font(.footnote)
                        .foregroundColor(.green)
                }
            }
            
            Section {
                Button(action: importCSV) {
                    Text("CSVを一括取り込み")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                }
                .listRowBackground(Color.blue)
                .disabled(csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    
    // 手動カード追加
    private func saveSingleCard() {
        let tags = tagInput
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let textFrontImgs = frontImagesInput
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        let textBackImgs = backImagesInput
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let finalFrontImgs = Array(Set(frontImageURLs + textFrontImgs))
        let finalBackImgs = Array(Set(backImageURLs + textBackImgs))
        
        let newCard = AnkiCard(
            frontText: frontText.trimmingCharacters(in: .whitespacesAndNewlines),
            backText: backText.trimmingCharacters(in: .whitespacesAndNewlines),
            frontType: frontType,
            explanation1: explanation1.trimmingCharacters(in: .whitespacesAndNewlines),
            explanation2: explanation2.trimmingCharacters(in: .whitespacesAndNewlines),
            explanation3: explanation3.trimmingCharacters(in: .whitespacesAndNewlines),
            japaneseTranslation: japaneseTranslation.trimmingCharacters(in: .whitespacesAndNewlines),
            exampleSentence: exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines),
            exampleTranslation: exampleTranslation.trimmingCharacters(in: .whitespacesAndNewlines),
            synonyms: synonyms.trimmingCharacters(in: .whitespacesAndNewlines),
            antonyms: antonyms.trimmingCharacters(in: .whitespacesAndNewlines),
            frontImageURLs: finalFrontImgs,
            backImageURLs: finalBackImgs,
            mainCategory: mainCategory.trimmingCharacters(in: .whitespacesAndNewlines),
            subCategory: subCategory.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags,
            isFavorite: isFavorite
        )
        
        onAddCards([newCard])
        
        // 連続追加用にフォームリセット
        frontText = ""
        backText = ""
        japaneseTranslation = ""
        exampleSentence = ""
        exampleTranslation = ""
        synonyms = ""
        antonyms = ""
        explanation1 = ""
        explanation2 = ""
        explanation3 = ""
        frontImageURLs = []
        backImageURLs = []
        frontImagesInput = ""
        backImagesInput = ""
        importedCountMessage = "1枚のカードを追加しました。"
    }
    
    // SEC-02: CSVパース処理 (サニタイズ・上限500枚バリデーション付き)
    private func importCSV() {
        let lines = csvText.components(separatedBy: .newlines)
        var newCards: [AnkiCard] = []
        let maxCardLimit = 500
        
        for line in lines {
            guard newCards.count < maxCardLimit else { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            let parts = trimmed.components(separatedBy: ",")
            if parts.count >= 2 {
                // サニタイズ: 各セルを最大 2,000 文字に制限
                let front = String(parts[0].trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
                let back = String(parts[1].trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
                var mainCat = ""
                var subCat = ""
                var tags: [String] = []
                
                if parts.count >= 3 {
                    mainCat = String(parts[2].trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
                }
                if parts.count >= 4 {
                    subCat = String(parts[3].trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
                }
                if parts.count >= 5 {
                    tags = parts[4...].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                
                if !front.isEmpty && !back.isEmpty {
                    newCards.append(
                        AnkiCard(
                            frontText: front,
                            backText: back,
                            mainCategory: mainCat,
                            subCategory: subCat,
                            tags: tags
                        )
                    )
                }
            }
        }
        
        if !newCards.isEmpty {
            onAddCards(newCards)
            importedCountMessage = "\(newCards.count) 枚のカードを正常に取り込みました！"
            csvText = ""
        }
    }
}
