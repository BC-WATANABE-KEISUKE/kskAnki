# 01. ブロッカー 🔴

出荷・実行が不可能、またはユーザーデータが失われる問題。**他のすべての指摘より優先して対応してください。**

---

<a id="blk-01"></a>

## BLK-01: iOSアプリターゲットが存在しない — 実機・シミュレータで起動できない

**深刻度**: 🔴 Blocker
**該当**: `Package.swift`, `src/App/kskAnkiApp.swift:6`

`Package.swift` は `kskAnkiCore` という **ライブラリターゲット** を1つ定義しているだけです。

```swift
.target(
    name: "kskAnkiCore",
    path: "src"          // ← @main を含む src/App/ もここに入っている
)
```

リポジトリ全体に以下が存在しません（`find` で確認済み）。

- `.xcodeproj` / `.xcworkspace`
- `Info.plist`
- `Assets.xcassets`（AppIcon、AccentColor）
- Bundle Identifier / 署名設定 / Launch Screen

つまり **現状のリポジトリからはiOSアプリを1度もビルド・起動できません**。`swift build` が通るのは「ライブラリとして型チェックが通る」ことを意味するだけで、アプリの動作保証ではありません。

ADR-0001 は「Xcode / SPM 環境ベースでコード・パッケージ管理を行う」と記載していますが、その前提となるXcodeプロジェクトが未作成です。

### 推奨対応

1. Xcodeで iOS App ターゲット (`kskAnki`) を作成する
2. `kskAnkiCore` をローカルSPMパッケージとして依存に追加する
3. `src/App/kskAnkiApp.swift` を**アプリターゲット側へ移動**する（ライブラリに `@main` を残さない）
4. Info.plist に最低限必要な項目を設定する
   - `UISupportedInterfaceOrientations` = Portrait のみ（要件1「iPhone縦画面表示に最適化」に合わせる）
   - `NSMicrophoneUsageDescription` 等は現状不要だが、将来の音声録音機能を入れる際に必要

---

<a id="blk-02"></a>

## BLK-02: `swift test` がリンクエラーで失敗する（テストが1件も実行されていない）

**深刻度**: 🔴 Blocker
**該当**: `src/App/kskAnkiApp.swift:6`, `Package.swift:19`

BLK-01 の直接的な帰結です。`@main` がライブラリターゲットに含まれているため、テストランナーの `main` と衝突します。実行結果:

```
duplicate symbol '_main' in:
    .../kskAnkiCore.build/kskAnkiApp.swift.o
    .../kskAnkiPackageTests.build/runner.swift.o
ld: 1 duplicate symbols
error: fatalError
```

**現時点でテストは1件も実行できていません。** CIを組んでも常に赤になります。

### 推奨対応

BLK-01 の対応（`@main` をアプリターゲットへ移動）でそのまま解消します。暫定対応が必要な場合は、`src/App/` をライブラリターゲットから除外してください。

```swift
.target(
    name: "kskAnkiCore",
    path: "src",
    exclude: ["App"]
)
```

---

<a id="blk-03"></a>

## BLK-03: データが一切永続化されない — 再起動で全学習履歴が消える

**深刻度**: 🔴 Blocker
**該当**: `src/Services/DeckStore.swift:6-20`, `src/App/kskAnkiApp.swift:7`

`DeckStore` は `@Observable final class` で、配列をメモリに保持しているだけです。保存・読込のコードがどこにもありません（`SwiftData` / `@Model` / `FileManager` / `JSONEncoder` の全文検索でヒット0件）。

```swift
@State private var deckStore = DeckStore()   // kskAnkiApp.swift:7 — 起動のたびに新規生成
```

結果として:

- 作成したコース・フォルダ・カードは**アプリを終了した瞬間に消滅**します
- ◯/△/✕ の判定、`easeFactor`、`dueDate`、マイメモも同様に消滅します
- 起動のたびに `sampleFolders` / `sampleCourses` / `sampleDecks` のデモデータが復活します

これは **REQUIREMENTS.md 4.3「データ永続性・即時性」に真っ向から違反**しており、また ADR-0001 が採用理由に挙げた「iOS 17/18最新のSwiftDataによるスマートなローカルストレージ」も未実装です。

暗記アプリにおいて学習履歴の喪失は致命的です。間隔反復は「過去の学習記録」の上にしか成立しません。

### 推奨対応

SwiftData を導入し、`@Model` クラスへ移行します。値型モデルは維持したい場合、SwiftData用の永続化エンティティを別途定義して DTO 変換する構成でも構いません（テスタビリティは値型のほうが高く保てます）。

```swift
// アプリターゲット側
@main
struct kskAnkiApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(for: [CourseEntity.self, DeckEntity.self, CardEntity.self, FolderEntity.self])
    }
}
```

**移行時の注意**: `AnkiCard` は既に `Codable` なので、暫定的に「アプリコンテナへのJSONダンプ」でも永続化自体は数十行で実現できます。SwiftData移行より先にこちらで血を止めるのも現実的な選択肢です。

---

<a id="blk-04"></a>

## BLK-04: 「マイ単語帳」からの学習結果が毎回破棄される

**深刻度**: 🔴 Blocker
**該当**: `src/Views/DeckListView.swift:118-120`

トップ画面の「マイ単語帳 (すべてのデッキ)」セクションから学習を開始する経路では、`onFinishSession` が渡されていません。

```swift
.sheet(item: $selectedDeckForStudy) { deck in
    CardStudyView(deck: deck)      // ← onFinishSession が nil
}
```

`CardStudyView` は判定結果をローカルの `@State dueCards` にしか書き込まず、セッション終了時に `onFinishSession?(...)` で外へ渡す設計です（`CardStudyView.swift:105, 215`）。コールバックが `nil` なので、**この経路で行った学習は、完了しても中断しても100%破棄されます。**

ユーザーから見ると「20枚まじめに判定したのに、何も記録されていない」という状態です。BLK-03（永続化なし）が直っても、この経路だけは別途直す必要があります。

### 推奨対応

`DeckStore` に更新を書き戻すコールバックを渡してください。

```swift
.sheet(item: $selectedDeckForStudy) { deck in
    CardStudyView(deck: deck) { sessionCards, shouldSave in
        guard shouldSave else { return }
        sessionCards.forEach { store.updateCard($0, inDeckId: deck.id) }
    }
}
```

なお、そもそも「コース配下のデッキ」と「マイ単語帳」が別世界になっている点自体が設計上の問題です → [ARC-01](02-architecture-and-data.md#arc-01) を参照。

---

<a id="blk-05"></a>

## BLK-05: シートを下スワイプで閉じると、確認なしに学習結果が消える

**深刻度**: 🔴 Blocker
**該当**: `src/Views/CardStudyView.swift:29`, `src/Views/CourseDetailView.swift:94`

`CardStudyView` はシートとして提示されており、iOSのシートは**デフォルトで下スワイプによるインタラクティブな dismiss が有効**です。

ナビゲーションバーの「中断」ボタンには `confirmationDialog` による保存確認が実装されています（要件3.3-④、`CardStudyView.swift:99-117`）。しかし下スワイプで閉じた場合はこのダイアログを通らず、`onFinishSession` も呼ばれないため、**判定もマイメモも無言で破棄されます。**

片手スワイプ操作（要件3.3-①）を主要な操作方法として推している以上、シート上での縦方向スワイプは頻繁に暴発します。「上スワイプ=△」を狙って失敗し、下方向に指が滑れば、それだけでセッションが消えます。危険度が高い組み合わせです。

### 推奨対応

インタラクティブ dismiss を無効化し、明示的な「中断」フローに一本化してください。

```swift
// CardStudyView の NavigationStack に付与
.interactiveDismissDisabled(true)
```

さらに、判定は「セッション終了時にまとめて保存」ではなく **1枚ごとに即時保存**する方式へ変更することを推奨します。要件4.3も「正誤判定、途中中断成果の即時状態反映」を求めています。即時保存にすればアプリのクラッシュ・強制終了でも結果が残り、「保存せずに中断」は「セッション開始時点へのロールバック」として別途実装するほうが堅牢です。
