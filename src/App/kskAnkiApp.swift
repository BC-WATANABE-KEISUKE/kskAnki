import SwiftUI

/// iPhoneアプリのエントリーポイント
@available(iOS 17.0, macOS 14.0, *)
@main
struct kskAnkiApp: App {
    @State private var deckStore = DeckStore()
    
    var body: some Scene {
        WindowGroup {
            DeckListView(store: deckStore)
        }
    }
}
