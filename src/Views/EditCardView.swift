import SwiftUI
import PhotosUI

/// カード編集画面 (RFC-01: CardEditorFormView 共通化)
@available(iOS 17.0, macOS 14.0, *)
public struct EditCardView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var card: AnkiCard
    @State private var formData: CardEditorInputData
    
    public let onSave: (AnkiCard) -> Void
    
    public init(card: AnkiCard, onSave: @escaping (AnkiCard) -> Void) {
        self._card = State(initialValue: card)
        
        var initialData = CardEditorInputData()
        initialData.frontType = card.frontType
        initialData.frontText = card.frontText
        initialData.backText = card.backText
        initialData.japaneseTranslation = card.japaneseTranslation
        initialData.frontImagesInput = card.frontImageURLs.joined(separator: ", ")
        initialData.backImagesInput = card.backImageURLs.joined(separator: ", ")
        initialData.explanation1 = card.explanation1
        initialData.explanation2 = card.explanation2
        initialData.exampleSentence = card.exampleSentence
        initialData.exampleTranslation = card.exampleTranslation
        initialData.mainCategory = card.mainCategory
        initialData.subCategory = card.subCategory
        initialData.tagsInput = card.tags.joined(separator: ", ")
        initialData.frontImageURLs = card.frontImageURLs
        initialData.backImageURLs = card.backImageURLs
        
        self._formData = State(initialValue: initialData)
        self.onSave = onSave
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CardEditorFormView(data: $formData)
                saveButtonSection
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
            }
            .onChange(of: formData.selectedFrontPhotoItems) { _, items in
                loadFrontPhotos(items)
            }
            .onChange(of: formData.selectedBackPhotoItems) { _, items in
                loadBackPhotos(items)
            }
        }
    }
    
    private var saveButtonSection: some View {
        Button(action: saveChanges) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("変更内容を保存")
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isFormValid ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(!isFormValid)
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
    
    private var isFormValid: Bool {
        !formData.frontText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !formData.backText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func saveChanges() {
        guard isFormValid else { return }
        
        var updated = card
        updated.frontType = formData.frontType
        updated.frontText = formData.frontText.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.backText = formData.backText.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.japaneseTranslation = formData.japaneseTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.explanation1 = formData.explanation1.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.explanation2 = formData.explanation2.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.exampleSentence = formData.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.exampleTranslation = formData.exampleTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.mainCategory = formData.mainCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.subCategory = formData.subCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        
        updated.frontImageURLs = formData.frontImageURLs
        updated.backImageURLs = formData.backImageURLs
        
        updated.tags = formData.tagsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        onSave(updated)
        dismiss()
    }
}
