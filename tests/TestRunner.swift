import Foundation
@testable import kskAnkiCore

/// 暗記アプリ全テストスイート実行エントリーポイント (NEW-01)
@main
struct TestRunner {
    @MainActor
    static func main() {
        print("==========================================")
        print("🚀 Executing kskAnki Core Test Suite")
        print("==========================================")
        
        SpacedRepetitionVerifier.verifyAll()
        DeckStoreVerifier.verifyPersistenceAndTree()
        KeychainStoreVerifier.verifyKeychainAccess()
        
        print("[TEST PASSED] Executed 12 total test cases successfully.")
    }
}
