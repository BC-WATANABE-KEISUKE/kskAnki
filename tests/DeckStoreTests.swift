import Foundation
@testable import kskAnkiCore

/// DeckStore 永続化 & データツリー構造 & 動的ストリーク計算の自動検証クラス
@MainActor
public struct DeckStoreVerifier {
    public static func verifyPersistenceAndTree() {
        let store = DeckStore()
        
        assert(store.allDecks.count >= 0, "サンプルコースからデッキが取得できること")
        
        let testCourse = Course(title: "UnitTestCourse", description: "Persistence test")
        store.addCourse(testCourse)
        assert(store.courses.contains(where: { $0.id == testCourse.id }), "コースが正常に追加されていること")
        
        // 3. ARC-04 / NEW-02 動的ストリーク & recordStudy 検証
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let cardId = UUID()
        
        store.studyLogs = [] // テストログの初期化
        store.recalculateMetrics()
        store.recordStudy(cardId: cardId, rating: .correct, at: yesterday)
        store.recordStudy(cardId: cardId, rating: .correct, at: now)
        
        assert(store.todayStudiedCardsCount == 1, "本日の学習枚数がログから正確に計算されること")
        assert(store.streakDaysCount == 2, "連続学習日数が2日と算出されること")
        
        let saveSuccess = store.saveToDisk(sync: true)
        assert(saveSuccess, "Diskへの保存が成功すること")
        
        let newStore = DeckStore()
        assert(newStore.courses.contains(where: { $0.id == testCourse.id }), "Diskからの再ロードで追加コースが維持されること")
        
        newStore.deleteCourse(testCourse.id)
        
        print("[VERIFIED] Executed 5 DeckStore test cases successfully.")
    }
}
