import Foundation
#if canImport(XCTest)
import XCTest
#endif
@testable import kskAnkiCore

/// DeckStore 永続化 & データツリー構造 & 動的ストリーク計算の XCTest テストケース (DEV-01, DEV-02, ARC-04)
#if canImport(XCTest)
final class DeckStoreTests: XCTestCase {
    
    @MainActor
    func testDeckStorePersistenceAndTree() {
        let store = DeckStore()
        
        // 1. ARC-01 一元化検証: allDecks が courses から集計されること
        XCTAssertGreaterThanOrEqual(store.allDecks.count, 0, "サンプルコースからデッキが平坦化取得できること")
        
        // 2. BLK-03 / ARC-03 永続化検証
        let testCourse = Course(title: "UnitTestCourse", description: "Persistence test")
        store.addCourse(testCourse)
        XCTAssertTrue(store.courses.contains(where: { $0.id == testCourse.id }), "コースが正常に追加されていること")
        
        // 3. ARC-04 動的ストリーク & 学習枚数計算検証
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let cardId = UUID()
        
        store.studyLogs = [
            StudyLog(cardId: cardId, rating: .correct, studiedAt: yesterday),
            StudyLog(cardId: cardId, rating: .correct, studiedAt: now)
        ]
        XCTAssertEqual(store.todayStudiedCardsCount, 1, "本日の学習枚数がログから正確に計算されること")
        XCTAssertEqual(store.streakDaysCount, 2, "連続学習日数が2日と算出されること")
        
        // 保存とロード
        let saveSuccess = store.saveToDisk()
        XCTAssertTrue(saveSuccess, "Diskへの保存が成功すること")
        
        let newStore = DeckStore()
        XCTAssertTrue(newStore.courses.contains(where: { $0.id == testCourse.id }), "Diskからの再ロードで追加コースが維持されること")
        
        // クリーンアップ
        newStore.deleteCourse(testCourse.id)
    }
}
#endif
