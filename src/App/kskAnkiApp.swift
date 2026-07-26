import SwiftUI

/// iPhoneアプリのエントリーポイント (NEW-03 / BLK-01: @main重複防止ガード付き)
@available(iOS 17.0, macOS 14.0, *)
public struct kskAnkiAppView: View {
    @State private var deckStore = DeckStore()
    
    public init() {}
    
    public var body: some View {
        DeckListView(store: deckStore)
    }
}

#if !SWIFT_PACKAGE
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
#endif
