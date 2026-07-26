import Foundation
@testable import kskAnkiCore

/// 間隔反復 (SRS-01 〜 SRS-06) アルゴリズム自動検証クラス
@MainActor
public struct SpacedRepetitionVerifier {
    public static func verifyAll() {
        let scheduler = SpacedRepetitionScheduler()
        let now = Date()
        
        // SRS-04
        var card = AnkiCard(frontText: "Q", backText: "A")
        assert(card.isUnlearned == true, "初回未学習カードは isUnlearned が true であること")
        card = scheduler.processReview(card: card, rating: .incorrect, currentDate: now)
        assert(card.isUnlearned == false, "✕ 評価後でも学習済み (isUnlearned == false) になること")
        
        // SRS-05
        var multiCard = AnkiCard(frontText: "Q2", backText: "A2")
        multiCard = scheduler.processReview(card: multiCard, rating: .correct, currentDate: now)
        assert(multiCard.consecutiveCorrectCount == 1, "初回正解でカウント1")
        multiCard = scheduler.processReview(card: multiCard, rating: .correct, currentDate: now)
        assert(multiCard.consecutiveCorrectCount == 1, "同日内の連打では正解カウントが増加しないこと")
        
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        multiCard = scheduler.processReview(card: multiCard, rating: .correct, currentDate: tomorrow)
        assert(multiCard.consecutiveCorrectCount == 2, "日を跨いだ正解でカウントが2に増加すること")
        
        // SRS-02 & SRS-06
        var easeCard = AnkiCard(frontText: "Q3", backText: "A3", intervalDays: 300, easeFactor: 2.48)
        for i in 1...10 {
            let futureDate = Calendar.current.date(byAdding: .day, value: i * 2, to: now)!
            easeCard = scheduler.processReview(card: easeCard, rating: .correct, currentDate: futureDate)
        }
        assert(easeCard.easeFactor <= 2.5, "easeFactor は上限 2.5 を超えないこと")
        assert(easeCard.intervalDays <= 365, "intervalDays は上限 365日 を超えないこと")
        
        // SRS-03
        var doubtfulCard = AnkiCard(frontText: "Q4", backText: "A4", reps: 3, intervalDays: 10)
        doubtfulCard = scheduler.processReview(card: doubtfulCard, rating: .doubtful, currentDate: now)
        assert(doubtfulCard.intervalDays < 10, "△ 評価で間隔が伸びず短縮されること")
        assert(doubtfulCard.consecutiveCorrectCount == 0, "△ 評価で連続正解カウントがリセットされること")
        
        print("[VERIFIED] Executed 4 SpacedRepetition test cases successfully.")
    }
}
