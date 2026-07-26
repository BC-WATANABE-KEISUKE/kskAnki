import Foundation
#if canImport(XCTest)
import XCTest
#endif
@testable import kskAnkiCore

/// KeychainStore (SEC-01) セキュア保存の XCTest テストケース (DEV-01, DEV-02)
#if canImport(XCTest)
final class KeychainStoreTests: XCTestCase {
    
    func testKeychainAccess() {
        let key = "test_api_key_xctest"
        let val = "sk-proj-test1234567890"
        
        // 保存
        let saved = KeychainStore.save(key: key, value: val)
        XCTAssertTrue(saved, "Keychainへの暗号化保存が成功すること")
        
        // 読み出し
        let loaded = KeychainStore.load(key: key)
        XCTAssertEqual(loaded, val, "Keychainからの安全な復元値が一致すること")
        
        // 削除
        let deleted = KeychainStore.delete(key: key)
        XCTAssertTrue(deleted, "Keychainの項目削除が成功すること")
        XCTAssertNil(KeychainStore.load(key: key), "削除後はnilが返ること")
    }
}
#endif
