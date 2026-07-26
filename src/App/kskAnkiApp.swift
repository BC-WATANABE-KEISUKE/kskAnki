import SwiftUI

/// iPhoneアプリのメインエントリービュー (NEW-03 / BLK-01 / NEW2-08)
@available(iOS 17.0, macOS 14.0, *)
public struct kskAnkiAppView: View {
    @State private var deckStore = DeckStore()
    
    public init() {}
    
    public var body: some View {
        DeckListView(store: deckStore)
    }
}
