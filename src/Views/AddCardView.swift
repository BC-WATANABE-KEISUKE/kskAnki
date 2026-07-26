import SwiftUI
import PhotosUI

/// 単語カード追加画面 (手動1枚追加 & CSV一括インポート対応 / RFC-01: CardEditorFormView 共通化)
@available(iOS 17.0, macOS 14.0, *)
public struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: Int = 0 // 0: 手動1枚追加, 1: CSV一括インポート
    @State private var formData: CardEditorInputData = CardEditorInputData()
    
    // CSVインポートステート
    @State private var csvText: String = ""
    @State private var csvErrorMessage: String?
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
    
    // RFC-01: 手動追加フォーム
    private var manualAddForm: some View {
        VStack(spacing: 0) {
            CardEditorFormView(data: $formData)
            submitButtonSection
        }
        .onChange(of: formData.selectedFrontPhotoItems) { _, items in
            loadFrontPhotos(items)
        }
        .onChange(of: formData.selectedBackPhotoItems) { _, items in
            loadBackPhotos(items)
        }
    }
    
    private var submitButtonSection: some View {
        Button(action: saveSingleCard) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("この単語カードを追加")
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isManualFormValid ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(!isManualFormValid)
        .padding(16)
    }
    
    private func loadFrontPhotos(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let path = try? ImageStore.saveImage(data: data) {
                    if !formData.frontImageURLs.contains(path) {
                        formData.frontImageURLs.append(path)
                    }
                }
            }
            formData.frontImagesInput = formData.frontImageURLs.joined(separator: ", ")
        }
    }
    
    private func loadBackPhotos(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let path = try? ImageStore.saveImage(data: data) {
                    if !formData.backImageURLs.contains(path) {
                        formData.backImageURLs.append(path)
                    }
                }
            }
            formData.backImagesInput = formData.backImageURLs.joined(separator: ", ")
        }
    }
    
    // CSV一括インポートフォーム
    private var csvImportForm: some View {
        Form {
            Section("CSVデータ入力 / 貼り付け") {
                TextEditor(text: $csvText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 180)
                
                Button("サンプルCSVフォーマットを挿入") {
                    csvText = """
                    Implementation,実装・実行,単語,プロジェクト計画をコード化・実行すること。,新方針の実行は来月開始。,Google Cloud,ACE,"ACE,重要"
                    "GCEにおける{{アクセス制御}}",事前定義されたロール,穴埋め,最小権限の原則に基づくベターアプローチ。,roles/compute.networkAdmin を推奨。,Google Cloud,IAM,"IAM,セキュリティ"
                    """
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if let err = csvErrorMessage {
                Section {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            if let msg = importedCountMessage {
                Section {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Section {
                Button(action: importCSV) {
                    HStack {
                        Image(systemName: "arrow.down.doc.fill")
                        Text("CSVを一括インポート")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                }
                .disabled(csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    
    private var isManualFormValid: Bool {
        !formData.frontText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !formData.backText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func saveSingleCard() {
        guard isManualFormValid else { return }
        
        let tags = formData.tagsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let newCard = AnkiCard(
            frontText: formData.frontText.trimmingCharacters(in: .whitespacesAndNewlines),
            backText: formData.backText.trimmingCharacters(in: .whitespacesAndNewlines),
            frontType: formData.frontType,
            explanation1: formData.explanation1.trimmingCharacters(in: .whitespacesAndNewlines),
            explanation2: formData.explanation2.trimmingCharacters(in: .whitespacesAndNewlines),
            japaneseTranslation: formData.japaneseTranslation.trimmingCharacters(in: .whitespacesAndNewlines),
            exampleSentence: formData.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines),
            exampleTranslation: formData.exampleTranslation.trimmingCharacters(in: .whitespacesAndNewlines),
            frontImageURLs: formData.frontImageURLs,
            backImageURLs: formData.backImageURLs,
            mainCategory: formData.mainCategory.trimmingCharacters(in: .whitespacesAndNewlines),
            subCategory: formData.subCategory.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags
        )
        
        onAddCards([newCard])
        dismiss()
    }
    
    private func importCSV() {
        csvErrorMessage = nil
        importedCountMessage = nil
        
        let lines = csvText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !lines.isEmpty else {
            csvErrorMessage = "CSVデータが空です。"
            return
        }
        
        guard lines.count <= 500 else {
            csvErrorMessage = "安全のため、1回のCSVインポートは最大 500枚までに制限されています。"
            return
        }
        
        var importedCards: [AnkiCard] = []
        
        for (idx, line) in lines.enumerated() {
            let sanitizedLine = String(line.prefix(2000))
            let columns = parseCSVLine(sanitizedLine)
            
            if columns.count >= 2 {
                let front = columns[0]
                let back = columns[1]
                let typeStr = columns.count > 2 ? columns[2] : "単語"
                let exp1 = columns.count > 3 ? columns[3] : ""
                let exSent = columns.count > 4 ? columns[4] : ""
                let mainCat = columns.count > 5 ? columns[5] : ""
                let subCat = columns.count > 6 ? columns[6] : ""
                let tagsStr = columns.count > 7 ? columns[7] : ""
                
                let frontType: CardFrontType = (typeStr == "穴埋め" || front.contains("{{") || front.contains("[")) ? .cloze : .word
                let tags = tagsStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                
                let card = AnkiCard(
                    frontText: front,
                    backText: back,
                    frontType: frontType,
                    explanation1: exp1,
                    exampleSentence: exSent,
                    mainCategory: mainCat,
                    subCategory: subCat,
                    tags: tags
                )
                importedCards.append(card)
            } else {
                csvErrorMessage = "\(idx + 1) 行目のフォーマットが不正です (最小 2 カラム「問題,解答」が必要です)。"
                return
            }
        }
        
        if !importedCards.isEmpty {
            importedCountMessage = "✅ \(importedCards.count) 枚の単語カードを正常に取り込みました！"
            onAddCards(importedCards)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                dismiss()
            }
        }
    }
    
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false
        
        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }
}
