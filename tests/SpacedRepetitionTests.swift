import Foundation
#if canImport(XCTest)
import XCTest
#endif
@testable import kskAnkiCore

/// 間隔反復 (SRS-01 〜 SRS-06) アルゴリズム XCTest テストケース
#if canImport(XCTest)
final class SpacedRepetitionTests: XCTestCase {
    
    private var scheduler: SpacedRepetitionScheduler!
    private var now: Date!
    
    @MainActor
    override func setUp() {
        super.setUp()
        scheduler = SpacedRepetitionScheduler()
        now = Date()
    }
    
    // SRS-04: 初回未学習カード判定のテスト
    @MainActor
    func testIsUnlearnedStatus() {
        var card = AnkiCard(frontText: "Q", backText: "A")
        XCTAssertTrue(card.isUnlearned, "初回未学習カードは isUnlearned が true であること")
        
        card = scheduler.processReview(card: card, rating: .incorrect, currentDate: now)
        XCTAssertFalse(card.isUnlearned, "✕ 評価後でも学習済み (isUnlearned == false) になること")
    }
    
    // SRS-05: 日を跨いだ連続正解カウント増加のテスト
    @MainActor
    func testConsecutiveCorrectCountOnlyIncreasesOnDifferentDays() {
        var card = AnkiCard(frontText: "Q2", backText: "A2")
        
        // 同日内の2回◯
        card = scheduler.processReview(card: card, rating: .correct, currentDate: now)
        XCTAssertEqual(card.consecutiveCorrectCount, 1, "初回正解でカウント1")
        
        card = scheduler.processReview(card: card, rating: .correct, currentDate: now)
        XCTAssertEqual(card.consecutiveCorrectCount, 1, "同日内の連打では正解カウントが増加しないこと")
        
        // 日を跨いだ場合
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        card = scheduler.processReview(card: card, rating: .correct, currentDate: tomorrow)
        XCTAssertEqual(card.consecutiveCorrectCount, 2, "日を跨いだ正解でカウントが2に増加すること")
    }
    
    // SRS-02 & SRS-06: easeFactor 及び intervalDays のキャップと日付計算のテスト
    @MainActor
    func testEaseFactorAndIntervalCaps() {
        var card = AnkiCard(frontText: "Q3", backText: "A3", intervalDays: 300, easeFactor: 2.48)
        
        for i in 1...10 {
            let futureDate = Calendar.current.date(byAdding: .day, value: i * 2, to: now)!
            card = scheduler.processReview(card: card, rating: .correct, currentDate: futureDate)
        }
        
        XCTAssertLessThanOrEqual(card.easeFactor, 2.5, "easeFactor は上限 2.5 を超えないこと")
        XCTAssertLessThanOrEqual(card.intervalDays, 365, "intervalDays は上限 365日 を超えないこと")
    }
    
    // SRS-03: 「△ 惜しい」評価時の間隔短縮テスト
    @MainActor
    func testDoubtfulRatingShortensInterval() {
        var card = AnkiCard(frontText: "Q4", backText: "A4", reps: 3, intervalDays: 10)
        card = scheduler.processReview(card: card, rating: .doubtful, currentDate: now)
        
        XCTAssertLessThan(card.intervalDays, 10, "△ 評価で間隔が伸びず短縮されること")
        XCTAssertEqual(card.consecutiveCorrectCount, 0, "△ 評価で連続正解カウントがリセットされること")
    }
    
    // SRS-01: 復習期日フィルタリングのテスト
    @MainActor
    func testStudyFilterDueToday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        
        let dueCard = AnkiCard(frontText: "Due", backText: "A", dueDate: yesterday, lastStudiedAt: yesterday)
        let futureDueCard = AnkiCard(frontText: "Future", backText: "A", dueDate: tomorrow, lastStudiedAt: now)
        
        let config = StudyFilterConfig(target: .dueToday, batchSize: 0)
        let results = config.filterCards([dueCard, futureDueCard], currentDate: now)
        
        XCTAssertTrue(results.contains(where: { $0.id == dueCard.id }), "期日到来カードが抽出されること")
        XCTAssertFalse(results.contains(where: { $0.id == futureDueCard.id }), "未来の期日カードは除外されること")
    }
}
#endif
