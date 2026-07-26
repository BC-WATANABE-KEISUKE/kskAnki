import Foundation

/// 間隔反復 (Spaced Repetition: ◯ / △ / ✕ 3段階対応) スケジューラー
public struct SpacedRepetitionScheduler: Sendable {
    
    public init() {}
    
    /// 回答評価 (Rating: ◯ / △ / ✕) に基づきカードの次回学習日・インターバルを更新する
    public func processReview(card: AnkiCard, rating: Rating, currentDate: Date = Date()) -> AnkiCard {
        var updatedCard = card
        
        // SRS-05: 同日内での連打判定を防ぐ (前回学習日時が同日でない場合のみ 4連勝カウントを進める)
        let isDifferentDayOrFirstTime: Bool
        if let lastStudied = card.lastStudiedAt {
            isDifferentDayOrFirstTime = !Calendar.current.isDate(lastStudied, inSameDayAs: currentDate)
        } else {
            isDifferentDayOrFirstTime = true
        }
        
        updatedCard.lastRating = rating
        updatedCard.lastStudiedAt = currentDate
        
        switch rating {
        case .incorrect: // ✕ 不正解
            updatedCard.reps = 0
            updatedCard.intervalDays = 0
            updatedCard.wrongCount += 1
            updatedCard.consecutiveCorrectCount = 0 // 連続正解リセット
            updatedCard.easeFactor = max(SRSParameters.minEaseFactor, updatedCard.easeFactor - 0.2)
            
        case .doubtful: // △ 惜しい (SRS-03: 復習間隔を伸ばさず半減短縮する)
            updatedCard.doubtfulCount += 1
            updatedCard.consecutiveCorrectCount = 0 // 連続正解リセット
            updatedCard.easeFactor = max(SRSParameters.minEaseFactor, updatedCard.easeFactor - 0.1)
            if updatedCard.reps == 0 {
                updatedCard.intervalDays = 1
            } else {
                updatedCard.intervalDays = max(1, Int(round(Double(max(1, updatedCard.intervalDays)) * 0.5)))
            }
            
        case .correct: // ◯ 正解
            updatedCard.reps += 1
            if isDifferentDayOrFirstTime {
                updatedCard.consecutiveCorrectCount += 1 // SRS-05: 日を跨いだ正解のみカウント
            }
            // SRS-02: easeFactor に上限 2.5 を適用
            updatedCard.easeFactor = min(SRSParameters.defaultEaseFactor, updatedCard.easeFactor + 0.05)
            if updatedCard.reps == 1 {
                updatedCard.intervalDays = 1
            } else if updatedCard.reps == 2 {
                updatedCard.intervalDays = 4
            } else {
                updatedCard.intervalDays = Int(round(Double(updatedCard.intervalDays) * updatedCard.easeFactor))
            }
        }
        
        // SRS-02: intervalDays に上限 365 日を設定
        updatedCard.intervalDays = min(SRSParameters.maxIntervalDays, updatedCard.intervalDays)
        
        // SRS-06: Calendar API で次回学習日を計算
        updatedCard.dueDate = Calendar.current.date(byAdding: .day, value: updatedCard.intervalDays, to: currentDate) ?? currentDate
        
        return updatedCard
    }
}
