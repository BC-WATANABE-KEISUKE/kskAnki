import SwiftUI

/// カード学習・復習画面 (iPhone最適化: ◯ △ ✕ 3択判定 & 片手スワイプジェスチャー & 中断確認・成果保存ダイアログ)
@available(iOS 17.0, macOS 14.0, *)
public struct CardStudyView: View {
    public let deck: AnkiDeck
    @State private var dueCards: [AnkiCard]
    @State private var sessionRatings: [(cardId: UUID, rating: Rating)] = []
    @State private var currentIndex: Int = 0
    @State private var isRevealed: Bool = false
    @State private var isCompleted: Bool = false
    
    // 片手スワイプ用ドラッグステート
    @State private var dragOffset: CGSize = .zero
    
    // 中断確認ダイアログステート
    @State private var isPauseConfirmationPresented: Bool = false
    
    // ARC-05: 設定配線 (Haptics 触覚効果フラグ)
    @AppStorage("enableHaptics") private var enableHaptics: Bool = true
    
    public let onFinishSession: (([AnkiCard], [(UUID, Rating)], Bool) -> Void)?
    public let onRecordRating: ((UUID, Rating) -> Void)?
    
    private let scheduler = SpacedRepetitionScheduler()
    @Environment(\.dismiss) private var dismiss
    
    public init(
        deck: AnkiDeck,
        onRecordRating: ((UUID, Rating) -> Void)? = nil,
        onFinishSession: (([AnkiCard], [(UUID, Rating)], Bool) -> Void)? = nil
    ) {
        self.deck = deck
        self._dueCards = State(initialValue: deck.cards)
        self.onRecordRating = onRecordRating
        self.onFinishSession = onFinishSession
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if isCompleted || dueCards.isEmpty {
                    completionView
                } else if currentIndex < dueCards.count {
                    let currentCard = dueCards[currentIndex]
                    
                    // 進捗プログレスバー (UX-09: 1枚目表示時は 0 / N から正調スタート)
                    progressHeader(current: currentIndex, total: dueCards.count)
                    
                    ZStack {
                        ScrollView {
                            // 表面・展開型裏面カードコンポーネント (メモ表示 & インライン編集対応)
                            FlashcardView(card: currentCard, isRevealed: $isRevealed) { updatedNote in
                                dueCards[currentIndex].userNotes = updatedNote
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        }
                        .offset(x: dragOffset.width, y: dragOffset.height)
                        .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                        .gesture(
                            isRevealed ? swipeGesture : nil
                        )
                        
                        // スワイプ方向ガイドオーバーレイ
                        if isRevealed && dragOffset != .zero {
                            swipeHintOverlay
                        }
                    }
                    
                    Spacer()
                    
                    // 裏面が開いたタイミングで ◯ △ ✕ 3択ボタンを表示
                    if isRevealed {
                        VStack(spacing: 8) {
                            Text("💡 ヒント: カードを右スワイプで ◯(正解)、左で ✕(不正解)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            threeStateRatingButtonsGroup(for: currentCard)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        // 未展開時の案内メッセージ
                        Text("カードをタップして解答を表示")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 24)
                    }
                }
            }
            .padding(.vertical, 8)
            .navigationTitle(deck.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("中断") {
                        if currentIndex > 0 || isRevealed {
                            isPauseConfirmationPresented = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .confirmationDialog(
                "学習を中断しますか？",
                isPresented: $isPauseConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("ここまでの成果を保存して中断") {
                    onFinishSession?(dueCards, sessionRatings, true)
                    dismiss()
                }
                
                Button("保存せずに中断", role: .destructive) {
                    onFinishSession?(deck.cards, [], false)
                    dismiss()
                }
                
                Button("学習を続ける", role: .cancel) {}
            } message: {
                Text("ここまでの復習結果（◯/△/✕判定およびメモ）を保存して終了するか選択してください。")
            }
        }
        .interactiveDismissDisabled(true) // BLK-05: 下スワイプによる成果無言破棄を防止
    }
    
    // UI-02: スワイプジェスチャー判定 (軸ロックによる縦スクロール誤爆防止: 右=◯ / 左=✕)
    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { gesture in
                dragOffset = gesture.translation
            }
            .onEnded { gesture in
                let w = gesture.translation.width
                let h = gesture.translation.height
                
                // 横方向の動きが支配的な場合のみスワイプ判定を確定
                if abs(w) > abs(h) * 1.5 && abs(w) > 90 {
                    if w > 0 {
                        // 右スワイプ ➔ ◯ 正解
                        handleRating(.correct)
                    } else {
                        // 左スワイプ ➔ ✕ 不正解
                        handleRating(.incorrect)
                    }
                }
                
                withAnimation(.spring()) {
                    dragOffset = .zero
                }
            }
    }
    
    // スワイプ中の視覚ヒントオーバーレイ
    @ViewBuilder
    private var swipeHintOverlay: some View {
        if dragOffset.width > 60 {
            Text("◯ 正解")
                .font(.title)
                .fontWeight(.black)
                .foregroundColor(.green)
                .padding(16)
                .background(Color.white.opacity(0.9))
                .cornerRadius(16)
                .shadow(radius: 4)
        } else if dragOffset.width < -60 {
            Text("✕ 不正解")
                .font(.title)
                .fontWeight(.black)
                .foregroundColor(.red)
                .padding(16)
                .background(Color.white.opacity(0.9))
                .cornerRadius(16)
                .shadow(radius: 4)
        }
    }
    
    // 進捗表示
    private func progressHeader(current: Int, total: Int) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(current), total: Double(total))
                .tint(.blue)
                .padding(.horizontal, 24)
            
            Text("カード \(current + 1) / \(total)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // 完了表示
    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.green)
            
            Text("本日の復習が完了しました！")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("素晴らしいペースです！すべての指定カードの判定が完了しました。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            Button(action: {
                onFinishSession?(dueCards, sessionRatings, true)
                dismiss()
            }) {
                Text("コース画面に戻る")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
        }
    }
    
    // ◯ △ ✕ 3択正誤判定ボタン
    private func threeStateRatingButtonsGroup(for card: AnkiCard) -> some View {
        HStack(spacing: 12) {
            // ✕ 不正解
            ratingButton(symbol: "✕", label: "不正解", rating: .incorrect, color: .red)
            
            // △ 惜しい
            ratingButton(symbol: "△", label: "惜しい", rating: .doubtful, color: .orange)
            
            // ◯ 正解
            ratingButton(symbol: "◯", label: "正解", rating: .correct, color: .green)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
    
    // UI-05: アクセシビリティ VoiceOver ラベル付き判定ボタン
    private func ratingButton(symbol: String, label: String, rating: Rating, color: Color) -> some View {
        Button(action: {
            handleRating(rating)
        }) {
            VStack(spacing: 4) {
                Text(symbol)
                    .font(.title2)
                    .fontWeight(.black)
                Text(label)
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rating.label)
        .accessibilityHint("このカードの理解度を記録して次のカードへ進みます")
    }
    
    private func handleRating(_ rating: Rating) {
        let currentCard = dueCards[currentIndex]
        let updatedCard = scheduler.processReview(card: currentCard, rating: rating)
        dueCards[currentIndex] = updatedCard
        
        // NEW-02: 判定ごとにリアルタイムで学習ログ記録コールバックを通知
        sessionRatings.append((cardId: currentCard.id, rating: rating))
        onRecordRating?(currentCard.id, rating)
        
        // ARC-05: 触覚フィードバックの実行
        if enableHaptics {
            #if canImport(UIKit)
            let generator = UIImpactFeedbackGenerator(style: rating == .correct ? .medium : .light)
            generator.impactOccurred()
            #endif
        }
        
        withAnimation(.easeInOut(duration: 0.25)) {
            isRevealed = false
            dragOffset = .zero
            if currentIndex + 1 < dueCards.count {
                currentIndex += 1
            } else {
                isCompleted = true
            }
        }
    }
}
