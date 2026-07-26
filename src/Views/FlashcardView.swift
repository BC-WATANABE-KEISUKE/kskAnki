import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 表面を表示し、タップすると下に裏面・複数画像・解説・類義語・ユーザーメモが展開表示されるコンポーネント (UI-01, UI-04, UI-05, UI-06, UI-07 改修)
@available(iOS 17.0, macOS 14.0, *)
public struct FlashcardView: View {
    public let card: AnkiCard
    @Binding public var isRevealed: Bool
    
    // メモ編集ステート
    @State private var isEditingNotes: Bool = false
    @State private var noteText: String = ""
    
    // 適応型ヒント開示ステート (デフォルトは完全隠し、タップで1文字目露出)
    @State private var showHint: Bool = false
    
    // 拡大表示モーダルステート
    @State private var selectedZoomImageURL: String? = nil
    
    // ARC-05: 設定配線 (自動音声再生フラグ)
    @AppStorage("enableAutoAudio") private var enableAutoAudio: Bool = true
    
    public let onSaveNotes: ((String) -> Void)?
    
    public init(card: AnkiCard, isRevealed: Binding<Bool>, onSaveNotes: ((String) -> Void)? = nil) {
        self.card = card
        self._isRevealed = isRevealed
        self.onSaveNotes = onSaveNotes
        self._noteText = State(initialValue: card.userNotes)
    }
    
    public var body: some View {
        // UI-01 & UI-07: ScrollView の二重ネストと maxHeight: 520 制限を排除し、VStack に一元化
        VStack(spacing: 0) {
            // 1. 表面 (問題 / 単語 / 穴埋め) エリア
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    // タイプ別バッジ表示
                    Text(card.frontType.badgeLabel)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(frontTypeColor(card.frontType))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(frontTypeColor(card.frontType).opacity(0.12))
                        .cornerRadius(8)
                    
                    if let categoryPath = card.categoryPath {
                        Text(categoryPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if card.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                            .accessibilityLabel("お気に入り登録済み")
                    }
                }
                
                // 表面メインコンテンツ (UI-06: Dynamic Type 追随フォント)
                frontContentView
                    .padding(.vertical, 12)
                
                // 表面画像一覧
                if !card.frontImageURLs.isEmpty {
                    imageGridView(urls: card.frontImageURLs)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(frontBgColor)
            
            // 2. 裏面 (展開時) エリア
            if isRevealed {
                VStack(alignment: .leading, spacing: 20) {
                    Divider()
                        .padding(.horizontal, 24)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        // 解答ヘッダー ＆ 音声再生ボタン
                        HStack {
                            Text("解答・解説")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                playBackSpeech()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "speaker.wave.2.fill")
                                    Text("朗読")
                                }
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("解答の音声を再生")
                        }
                        
                        // 解答メインテキスト
                        Text(card.backText)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundColor(.primary)
                        
                        // 日本語訳 / 和訳
                        if !card.japaneseTranslation.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("【日本語訳】")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(card.japaneseTranslation)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        // 例文 & 例文和訳
                        if !card.exampleSentence.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("【例文】")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(card.exampleSentence)
                                    .font(.subheadline)
                                    .italic()
                                    .foregroundColor(.primary)
                                if !card.exampleTranslation.isEmpty {
                                    Text(card.exampleTranslation)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        // 解説 1 / 2 / 3
                        if !card.explanation1.isEmpty || !card.explanation2.isEmpty || !card.explanation3.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("【解説】")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                if !card.explanation1.isEmpty {
                                    Text("• \(card.explanation1)").font(.footnote)
                                }
                                if !card.explanation2.isEmpty {
                                    Text("• \(card.explanation2)").font(.footnote)
                                }
                                if !card.explanation3.isEmpty {
                                    Text("• \(card.explanation3)").font(.footnote)
                                }
                            }
                        }
                        
                        // 類義語 / 反対語
                        if !card.synonyms.isEmpty || !card.antonyms.isEmpty {
                            HStack(spacing: 16) {
                                if !card.synonyms.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("類義語").font(.caption2).foregroundColor(.secondary)
                                        Text(card.synonyms).font(.caption).fontWeight(.semibold)
                                    }
                                }
                                if !card.antonyms.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("対義語").font(.caption2).foregroundColor(.secondary)
                                        Text(card.antonyms).font(.caption).fontWeight(.semibold)
                                    }
                                }
                            }
                        }
                        
                        // 裏面画像一覧
                        if !card.backImageURLs.isEmpty {
                            imageGridView(urls: card.backImageURLs)
                        }
                        
                        // タグ一覧
                        if !card.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(card.tags, id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.caption2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.gray.opacity(0.12))
                                            .cornerRadius(6)
                                    }
                                }
                            }
                        }
                        
                        // マイメモ（インライン編集機能対応）
                        myNotesSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(cardBgColor)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        .onTapGesture {
            if !isRevealed {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isRevealed = true
                }
            }
        }
        .onChange(of: isRevealed) { _, newValue in
            if newValue && enableAutoAudio {
                playBackSpeech()
            }
        }
        .sheet(item: Binding(
            get: { selectedZoomImageURL.map { ZoomImageItem(url: $0) } },
            set: { selectedZoomImageURL = $0?.url }
        )) { item in
            ImageDetailView(urlString: item.url)
        }
        .onChange(of: card.id) {
            noteText = card.userNotes
            showHint = false
        }
    }
    
    // 表面タイプ別の表示コンポーネント (UI-06 Dynamic Type 対応)
    @ViewBuilder
    private var frontContentView: some View {
        switch card.frontType {
        case .question:
            Text(card.frontText)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(.primary)
                .lineSpacing(4)
            
        case .word:
            VStack(spacing: 8) {
                Text(card.frontText)
                    .font(.custom("", size: 32, relativeTo: .largeTitle).weight(.black))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Button(action: playFrontSpeech) {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2.fill")
                        Text("発音を聴く")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("単語の発音を聴く")
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
        case .cloze:
            clozeFrontView
        }
    }
    
    // 穴埋め表現ビュー (UI-05 VoiceOver タップヒント対応)
    private var clozeFrontView: some View {
        let (maskedText, firstChar) = parseCloze(card.frontText)
        
        return VStack(alignment: .leading, spacing: 8) {
            Text(maskedText)
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundColor(.primary)
                .lineSpacing(6)
            
            HStack(spacing: 6) {
                if showHint, let hint = firstChar {
                    Text("💡 ヒント: \(hint) で始まる単語")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .transition(.opacity)
                } else {
                    Button(action: {
                        withAnimation { showHint = true }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                            Text("[❓伏せ字をタップで頭文字ヒント開示]")
                        }
                        .font(.caption)
                        .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("穴埋めの頭文字ヒントを開示")
                }
            }
        }
    }
    
    // 穴埋めマスクのパーサー
    private func parseCloze(_ text: String) -> (String, String?) {
        guard let regex = try? NSRegularExpression(pattern: "\\{\\{(.+?)\\}\\}|\\[(.+?)\\]", options: []) else {
            return (text, nil)
        }
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        guard let firstMatch = matches.first else {
            return (text, nil)
        }
        
        let targetRange = firstMatch.range(at: 1).location != NSNotFound ? firstMatch.range(at: 1) : firstMatch.range(at: 2)
        let targetWord = nsString.substring(with: targetRange)
        let firstChar = targetWord.first.map { String($0) }
        
        let masked: String
        if showHint, let char = firstChar {
            masked = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: "\(char)[ ❓ 隠し ]")
        } else {
            masked = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: "[ ❓ 隠し ]")
        }
        
        return (masked, firstChar)
    }
    
    // UI-04: ローカル画像 & リモート画像の一元描画グリッド
    private func imageGridView(urls: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, urlString in
                    cardImageView(urlString: urlString)
                        .frame(width: 140, height: 100)
                        .cornerRadius(12)
                        .clipped()
                        .onTapGesture {
                            selectedZoomImageURL = urlString
                        }
                        .accessibilityLabel("画像 \(index + 1) 枚目")
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
    
    // UI-04: ローカル画像（ImageStore）とリモート画像（AsyncImage）を両方レンダリング
    @ViewBuilder
    private func cardImageView(urlString: String) -> some View {
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://"), let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.gray.opacity(0.12).overlay(Image(systemName: "photo.fill").foregroundColor(.gray))
                }
            }
        } else {
            #if canImport(UIKit)
            if let uiImage = ImageStore.loadImage(path: urlString) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.12).overlay(Image(systemName: "photo.fill").foregroundColor(.gray))
            }
            #else
            Color.gray.opacity(0.12).overlay(Image(systemName: "photo.fill").foregroundColor(.gray))
            #endif
        }
    }
    
    // ユーザー個人メモエリア
    private var myNotesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("マイメモ", systemImage: "note.text")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    if isEditingNotes {
                        onSaveNotes?(noteText)
                    }
                    withAnimation { isEditingNotes.toggle() }
                }) {
                    Text(isEditingNotes ? "保存" : "編集")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            
            if isEditingNotes {
                TextField("このカードに関するメモを入力...", text: $noteText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.footnote)
            } else {
                Text(noteText.isEmpty ? "メモは登録されていません (タップして編集)" : noteText)
                    .font(.footnote)
                    .foregroundColor(noteText.isEmpty ? .secondary : .primary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.06))
                    .cornerRadius(8)
                    .onTapGesture {
                        withAnimation { isEditingNotes = true }
                    }
            }
        }
        .padding(.top, 4)
    }
    
    private func frontTypeColor(_ type: CardFrontType) -> Color {
        switch type {
        case .question: return .blue
        case .word: return .orange
        case .cloze: return .purple
        }
    }
    
    private var frontBgColor: Color {
        #if canImport(UIKit)
        return Color(uiColor: .tertiarySystemGroupedBackground)
        #else
        return Color.gray.opacity(0.08)
        #endif
    }
    
    private var cardBgColor: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color.gray.opacity(0.12)
        #endif
    }
    
    private func playFrontSpeech() {
        AudioService.shared.speak(text: card.frontText, language: card.speechLanguage)
    }
    
    private func playBackSpeech() {
        AudioService.shared.speak(text: card.backText, language: card.speechLanguage)
    }
}

private struct ZoomImageItem: Identifiable {
    let id = UUID()
    let url: String
}
