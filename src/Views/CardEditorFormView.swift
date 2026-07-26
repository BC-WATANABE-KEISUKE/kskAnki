import SwiftUI
import PhotosUI

/// 単語カードフォーム入力データ (RFC-01: コンパイル型推論最適化)
public struct CardEditorInputData: Sendable {
    public var frontType: CardFrontType = .word
    public var frontText: String = ""
    public var backText: String = ""
    public var japaneseTranslation: String = ""
    public var frontImagesInput: String = ""
    public var backImagesInput: String = ""
    public var explanation1: String = ""
    public var explanation2: String = ""
    public var exampleSentence: String = ""
    public var exampleTranslation: String = ""
    public var mainCategory: String = ""
    public var subCategory: String = ""
    public var tagsInput: String = ""
    
    public var selectedFrontPhotoItems: [PhotosPickerItem] = []
    public var selectedBackPhotoItems: [PhotosPickerItem] = []
    public var frontImageURLs: [String] = []
    public var backImageURLs: [String] = []
    
    public init() {}
}

/// 単語カード入力・編集用共通フォームコンポーネント (RFC-01: 型推論最適化・Form自己内包型)
@available(iOS 17.0, macOS 14.0, *)
public struct CardEditorFormView: View {
    @Binding public var data: CardEditorInputData
    
    public init(data: Binding<CardEditorInputData>) {
        self._data = data
    }
    
    public var body: some View {
        Form {
            styleSection
            frontSection
            backSection
            mediaSection
            explanationSection
            categorySection
        }
    }
    
    private var styleSection: some View {
        Section("表面のパターン (表示スタイル)") {
            Picker("表面パターン", selection: $data.frontType) {
                ForEach(CardFrontType.allCases) { type in
                    Label(type.rawValue, systemImage: type.iconName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            if data.frontType == .cloze {
                Text("💡 穴埋め設定ヒント: 文章内の隠したいキーワードを {{英単語}} または [英単語] で囲むと自動でマスク伏せ字になります。")
                    .font(.caption)
                    .foregroundColor(.purple)
            } else if data.frontType == .word {
                Text("💡 単語スタイル: 英単語やフレーズを画面中央に強調して大きく表示します。")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }
    
    private var frontSection: some View {
        Section("表面 (Question / Front)") {
            TextField("問題・表側のテキストを入力", text: $data.frontText, axis: .vertical)
                .lineLimit(3...6)
        }
    }
    
    private var backSection: some View {
        Section("裏面 (Answer / Back)") {
            TextField("解答テキストを入力", text: $data.backText, axis: .vertical)
                .lineLimit(3...6)
            TextField("日本語訳 / 和訳", text: $data.japaneseTranslation)
        }
    }
    
    private var mediaSection: some View {
        Group {
            Section("📷 表面の画像 (Question Images)") {
                TextField("画像Web URL (カンマ区切り)", text: $data.frontImagesInput)
                
                PhotosPicker(selection: $data.selectedFrontPhotoItems, maxSelectionCount: 5, matching: .images) {
                    Label("フォトライブラリから画像を選択", systemImage: "photo.badge.plus")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                if !data.frontImageURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("登録予定の表面画像 (\(data.frontImageURLs.count)枚):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(data.frontImageURLs, id: \.self) { url in
                            HStack {
                                Image(systemName: "photo")
                                    .foregroundColor(.blue)
                                Text(url)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Spacer()
                                Button(action: {
                                    data.frontImageURLs.removeAll { $0 == url }
                                    data.frontImagesInput = data.frontImageURLs.joined(separator: ", ")
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }
            
            Section("🖼️ 裏面の解説画像 (Answer Images)") {
                TextField("解説画像Web URL (カンマ区切り)", text: $data.backImagesInput)
                
                PhotosPicker(selection: $data.selectedBackPhotoItems, maxSelectionCount: 5, matching: .images) {
                    Label("フォトライブラリから裏面画像を選択", systemImage: "photo.badge.plus")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                if !data.backImageURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("登録予定の裏面画像 (\(data.backImageURLs.count)枚):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(data.backImageURLs, id: \.self) { url in
                            HStack {
                                Image(systemName: "photo")
                                    .foregroundColor(.blue)
                                Text(url)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Spacer()
                                Button(action: {
                                    data.backImageURLs.removeAll { $0 == url }
                                    data.backImagesInput = data.backImageURLs.joined(separator: ", ")
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var explanationSection: some View {
        Group {
            Section("詳細解説・補足情報") {
                TextField("解説1 (主要な意味・文法・重要度のポイント)", text: $data.explanation1, axis: .vertical)
                    .lineLimit(2...4)
                TextField("解説2 (類義語・対義語・引っかけ注意点)", text: $data.explanation2, axis: .vertical)
                    .lineLimit(2...4)
            }
            
            Section("例文 & 例文訳") {
                TextField("例文 (Example Sentence)", text: $data.exampleSentence, axis: .vertical)
                    .lineLimit(2...4)
                TextField("例文の日本語訳", text: $data.exampleTranslation, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }
    
    private var categorySection: some View {
        Section("カテゴリー・タグ分類") {
            TextField("大カテゴリー (例: Google Cloud, 英語)", text: $data.mainCategory)
            TextField("中カテゴリー (例: IAM, 文法)", text: $data.subCategory)
            TextField("タグ (カンマ区切り 例: 頻出, 復習要)", text: $data.tagsInput)
        }
    }
}
