import Foundation
@testable import kskAnkiCore

/// KeychainStore (SEC-01) セキュア保存の自動検証クラス
public struct KeychainStoreVerifier {
    public static func verifyKeychainAccess() {
        let key = "test_api_key_verified"
        let val = "sk-proj-test1234567890"
        
        let saved = KeychainStore.save(key: key, value: val)
        assert(saved, "Keychainへの暗号化保存が成功すること")
        
        let loaded = KeychainStore.load(key: key)
        assert(loaded == val, "Keychainからの安全な復元値が一致すること")
        
        let deleted = KeychainStore.delete(key: key)
        assert(deleted, "Keychainの項目削除が成功すること")
        assert(KeychainStore.load(key: key) == nil, "削除後はnilが返ること")
        
        print("[VERIFIED] Executed 3 KeychainStore test cases successfully.")
    }
}
