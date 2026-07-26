import Foundation

/// JSONバックアップ・エクスポート＆リストアサービス (FEAT-03)
public struct BackupService: Sendable {
    
    /// DeckStore の全データを JSON 文字列としてエクスポート
    @MainActor
    public static func exportBackupJSON(store: DeckStore) -> String? {
        let snapshot = DeckStoreSnapshot(
            folders: store.folders,
            courses: store.courses,
            studyLogs: store.studyLogs,
            dailyGoalCardsCount: store.dailyGoalCardsCount
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(snapshot),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
    
    /// JSON 文字列から DeckStore へ全データを復元・リストア
    @MainActor
    public static func importBackupJSON(jsonString: String, store: DeckStore) -> Bool {
        guard let data = jsonString.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(DeckStoreSnapshot.self, from: data) else {
            return false
        }
        
        store.folders = snapshot.folders
        store.courses = snapshot.courses
        store.studyLogs = snapshot.studyLogs
        store.dailyGoalCardsCount = snapshot.dailyGoalCardsCount
        store.recalculateMetrics()
        store.saveToDisk()
        return true
    }
}
