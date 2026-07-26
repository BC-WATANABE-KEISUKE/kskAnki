# 08. 追補レビュー（修正対応後の再検証）

- **レビュー日**: 2026-07-26（2回目）
- **対象**: 初回レビュー（[01](01-blockers.md)〜[07](07-requirements-traceability.md)、全51件）への対応後の全ソース（4,301行 / 27ファイル）
- **検証方法**: 全ソース再精読 + `swift build` / `swift test` の実行 + 論点ごとの実行検証スクリプト

---

## 総評

**大きく前進しています。** 初回指摘51件のうち19件が完全に解消し、13件が部分解消しました。特に以下は設計の筋が良く、素直に評価できる修正です。

- **SRSアルゴリズムの是正（SRS-01〜06）が全て正しく入っています。** `dueToday` / `overdue` フィルタの追加、`easeFactor` の 2.5 キャップ、`△` の間隔半減、`isUnlearned` を `lastStudiedAt == nil` に変更、日跨ぎ判定。中核ロジックの正しさは初回レビュー時から別物になりました
- **永続化（BLK-03）が入り、`DeckStore` が `@MainActor` に整理され、`store.decks` の二重世界（ARC-01）が解消**されました
- **PhotosPicker（UX-03）とローカル画像描画（UX-04）が `ImageStore` 経由で正しく実装**され、`FlashcardView` / `ImageDetailView` の両方で動作する形になっています
- ネストScrollView（UX-01）、`maxHeight: 520`（UX-07）、Dynamic Type（UX-06）の解消は、指摘した通りの修正が入っています

一方で、**再検証の結果、実行して初めて分かる重大な問題が3件見つかりました。**

1. **テストが1件も実行されていません。** `swift test` は終了コード0を返しますが、`#if canImport(XCTest)` により全テストがコンパイル対象から消えています（このMacにはフルXcodeが無く `canImport(XCTest)` が false）。**成功と区別できない偽グリーン**です
2. **ストリーク・学習統計が、メインの学習動線では一切記録されません。** `StudyLog` を追加するのは `DeckStore.updateCard` だけで、コース経由の学習（トップ→コース→学習を開始）はこの関数を通りません。ARC-04 の「偽データ」は「常に0」に変わっただけです
3. **BLK-01（アプリターゲット不在）が未対応のままです。** `.xcodeproj` / `Info.plist` / `Assets.xcassets` はいずれも作成されておらず、**iOSアプリとしては依然として1度も起動できません**。加えて `Package.swift` の `exclude: ["App"]` により、アプリのエントリポイント `kskAnkiApp.swift` が**コンパイル対象から外れ、型チェックすらされない状態**になりました

また、修正の過程で**要件を満たしていた機能が失われたリグレッションが3件**あります（表面の朗読ボタン、カテゴリーバッジ、穴埋めヒントの正しさ）。

---

## 対応状況サマリー

| 区分 | 件数 | 内訳 |
|---|---|---|
| ✅ 完全対応 | 19 | BLK-02〜05, ARC-01/03/08/09, SRS-01〜06, UX-01/03/04/06/07 |
| ⚠️ 部分対応 | 13 | ARC-02/04/05/06/07, UX-02/05/08, SEC-01, QA-01/02/06/08 |
| ❌ 未対応 | 19 | BLK-01, SRS-07/08, UX-09〜16, SEC-02〜05, QA-03/04/05/07 |
| 🆕 新規指摘 | 19 | 本ドキュメントで詳述（🔴3 / 🟠6 / 🟡8 / 🔵2） |

---

# 🔴 新規・継続ブロッカー

<a id="new-01"></a>

## NEW-01: `swift test` が成功するが、テストは1件も実行されていない

**深刻度**: 🔴 Blocker

3つのテストファイルが XCTest で正しく書かれた点は QA-01 への適切な対応です。しかし全ファイルが以下の形になっています。

```swift
#if canImport(XCTest)
import XCTest
#endif
@testable import kskAnkiCore

#if canImport(XCTest)          // ← ここから
final class SpacedRepetitionTests: XCTestCase { ... }
#endif                          // ← ここまで丸ごと消える可能性がある
```

**実測結果**（このMac上）:

```
$ swift test
Building for debugging...
Build complete! (0.09s)
$ echo $?
0
```

テストスイート名も、実行件数も、1行も出力されません。原因を切り分けたところ:

```
$ cat probe.swift
#if canImport(XCTest)
print("XCTest: AVAILABLE")
#else
print("XCTest: NOT AVAILABLE")
#endif
$ swiftc -o probe probe.swift && ./probe
XCTest: NOT AVAILABLE
```

この環境にはフルXcodeが無く（`/Library/Developer/CommandLineTools` のみ）、**`canImport(XCTest)` が false → 全テストクラスがソースごと消滅 → 空のテストバンドルがビルドされ、0件実行で正常終了**しています。

これは単なる環境問題ではなく、**設計上の欠陥**です。

- 開発機で `swift test` を実行しても、**永久に「成功」しか返りません**。テストを壊しても気づけません
- `scripts/run_tests.sh` は `set -e` の後に「✅ All tests passed successfully!」と出力するため、**0件実行でも成功メッセージが出ます**
- CI（`macos-14` + Xcode選択）では XCTest が使えるためテストは走りますが、**ローカルとCIで挙動が食い違う**構成は、CI失敗の原因究明を著しく困難にします

### 推奨対応

`#if canImport(XCTest)` によるサイレントスキップを**やめてください**。XCTestが無い環境ではテストがビルドできない、という状態のほうが安全です。

```swift
// ガードを外し、素直に import する
import XCTest
@testable import kskAnkiCore

final class SpacedRepetitionTests: XCTestCase { ... }
```

Swift 6 を使っているので、`swift-testing` に移行すればツールチェーン同梱のため環境差がそもそも生じません（初回レビュー QA-01 で提案した形）。

CI にも「0件実行を失敗扱いにする」ガードを入れてください。

```yaml
- name: Run swift test
  run: |
    swift test --enable-code-coverage 2>&1 | tee test.log
    grep -qE "Executed [1-9][0-9]* test" test.log || { echo "::error::テストが1件も実行されていません"; exit 1; }
```

また、このMacにはフルXcodeが入っていません。BLK-01（iOSアプリ化）を進めるにはXcodeのインストールが前提になります。

---

<a id="new-02"></a>

## NEW-02: コース経由の学習が学習ログに記録されない — ストリーク・統計が常に0

**深刻度**: 🔴 Blocker
**該当**: `src/Services/DeckStore.swift:186-188`, `src/Views/CourseDetailView.swift:87-93, 264-288`

ARC-04 への対応として `StudyLog` と動的なストリーク計算が実装されました。計算ロジック自体は正しく書けています（`DeckStore.swift:47-73`）。

しかし **`studyLogs` にログを追加するコードは、リポジトリ全体で1箇所しかありません**。

```
$ grep -rn "studyLogs.append" src
src/Services/DeckStore.swift:188:    studyLogs.append(log)
```

これは `DeckStore.updateCard(_:inDeckId:)` の中にあり、その呼び出し元も1箇所だけです。

```
$ grep -rn "store.updateCard" src
src/Views/DeckListView.swift:139:  sessionCards.forEach { store.updateCard($0, inDeckId: deck.id) }
src/Views/DeckListView.swift:146:  sessionCards.forEach { store.updateCard($0, inDeckId: deck.id) }
```

つまり **「マイ単語帳」セクションから学習した場合しか記録されません。**

主要な学習動線はこちらです。

```
トップ画面 → コースカード「コース詳細 / 学習」 → 学習を開始する → 判定
  ↓
CardStudyView の onFinishSession
  ↓
CourseDetailView.updateSingleCardInCourse(card)      ← StudyLog を追加しない
  ↓
onSaveCourse(updatedCourse) → DeckListView → store.updateCourse(...)   ← StudyLog を追加しない
```

結果として、通常の使い方をしている限り:

- 🔥 ストリークは**常に「0日連続学習中！」**
- 本日の目標は**常に「0 / 20 枚」**
- 新設の学習統計ダッシュボード（`StudyStatsView`）は、7日間グラフも判定内訳も**すべて0**

初回レビューで指摘した「ハードコードされた偽データ」は解消されましたが、**代わりに「常にゼロ」になっただけ**で、ユーザーから見た価値は戻っていません。

### 推奨対応

ログ記録の責務を、カード更新の副作用から切り離してください。判定が確定した瞬間（`CardStudyView.handleRating`）に記録するのが最も確実です。

```swift
// DeckStore に明示的なAPIを用意する
public func recordStudy(cardId: UUID, rating: Rating, at date: Date = Date()) {
    studyLogs.append(StudyLog(cardId: cardId, rating: rating, studiedAt: date))
    saveToDisk()
}
```

そのうえで、`CardStudyView` がセッション結果とあわせて判定履歴を返すか、`DeckStore` を環境オブジェクトとして受け取り、判定ごとに `recordStudy` を呼ぶ形にします。**両方の学習経路（コース / マイ単語帳）が同じ関数を通る**ようにするのが要点です。

なお現在の実装は `DeckStore.updateCard` の中で

```swift
let log = StudyLog(cardId: card.id, rating: card.lastRating ?? .correct, studiedAt: Date())
```

としており、「カードの更新＝学習イベント」と見なしています。将来 `updateCard` を編集用途にも使うと、**編集しただけで「◯ 正解」のログが積まれます**（`?? .correct` のフォールバックが特に危険です）。この点でも責務の分離が必要です。

---

<a id="new-03"></a>

## NEW-03: BLK-01 未対応 — さらにアプリのエントリポイントがコンパイルされなくなった

**深刻度**: 🔴 Blocker
**該当**: `Package.swift:20`, `src/App/kskAnkiApp.swift`

BLK-02（`swift test` のリンクエラー）は解消されましたが、その手段は初回レビューで**暫定対応**として提示した `exclude: ["App"]` でした。

```swift
.target(
    name: "kskAnkiCore",
    path: "src",
    exclude: ["App"]        // ← 暫定対応のまま
)
```

BLK-01 の本体（Xcodeプロジェクトの作成、`@main` のアプリターゲットへの移動）は未着手で、リポジトリには依然として以下がありません。

- `.xcodeproj` / `.xcworkspace`
- `Info.plist`（画面向きロック、Privacy Manifest）
- `Assets.xcassets`（AppIcon / AccentColor）
- Bundle Identifier / 署名設定

**iOSアプリとしては、初回レビュー時点と同様に1度も起動できません。**

加えて、この暫定対応により**新たな問題が生じています**。ビルドログを確認すると `kskAnkiApp.swift` はコンパイル対象に含まれていません。

```
[4/26] Compiling kskAnkiCore DeckStore.swift
...
[26/26] Compiling kskAnkiCore EditCardView.swift      ← kskAnkiApp.swift は無い
```

つまり **アプリの起動点が型チェックすらされていません**。たとえば `DeckStore` は今回 `@MainActor` になりましたが、それを `@State private var deckStore = DeckStore()` で初期化している `kskAnkiApp.swift` が正しくコンパイルできるかは**誰も検証していない**状態です。この種の齟齬は、Xcodeプロジェクトを作った瞬間にまとめて噴出します。

### 推奨対応

`exclude` に頼らず、本来の構成に移行してください。

1. Xcode をインストールする（現在このMacにはCommand Line Toolsのみ）
2. iOS App ターゲット `kskAnki` を作成し、`kskAnkiCore` をローカルパッケージ依存として追加
3. `src/App/kskAnkiApp.swift` をアプリターゲットへ**移動**（`exclude` は不要になる）
4. Info.plist に `UISupportedInterfaceOrientations`（Portrait固定）と `PrivacyInfo.xcprivacy`（`UserDefaults` の Required Reason API 申告）を設定

---

# 🟠 新規リグレッション・重大な新規問題

<a id="new-04"></a>

## NEW-04: 穴埋めが複数ある場合、2つ目以降に**誤った頭文字**が表示される

**深刻度**: 🟠 High
**該当**: `src/Views/FlashcardView.swift:316-339`

UX-15（キャプチャグループでの単語抽出）と UX-16（ヒント開示）への対応として `parseCloze` が書き直されましたが、**全てのマッチを「最初のマッチの頭文字」で一括置換**しています。

```swift
let targetRange = firstMatch.range(at: 1)... // ← 最初のマッチのみ
let firstChar = targetWord.first.map { String($0) }
...
masked = regex.stringByReplacingMatches(..., withTemplate: "\(char)[ ❓ 隠し ]")  // ← 全マッチに同じ文字
```

**実行検証結果**（`parseCloze` と同一ロジックを抽出して実行）:

```
■ 複数空欄
  入力      : I ate an {{apple}} and a {{banana}}.
  ヒント無し: I ate an [ ❓ 隠し ] and a [ ❓ 隠し ].
  ヒント有り: I ate an a[ ❓ 隠し ] and a a[ ❓ 隠し ].   ← banana なのに "a"
```

`banana` の頭文字が `b` ではなく `a` と表示されます。**ヒント機能が誤情報を提示する**ため、学習者を積極的に誤答へ誘導します。UX-16 で指摘した「全空欄が同時に開示される」問題も解消していません（むしろ誤った文字で開示されるぶん悪化しています）。

さらに UX-15（`[...]` の誤爆）も未解消であることが確認できました。

```
■ 角括弧の誤爆
  入力      : 配列の先頭は array[0] で参照する。
  ヒント無し: 配列の先頭は array[ ❓ 隠し ] で参照する。
  ヒント有り: 配列の先頭は array0[ ❓ 隠し ] で参照する。
```

本プロジェクトの主要コンテンツ（Google Cloud ACE、基本情報技術者）で頻出する記法です。

### 推奨対応

空欄ごとに独立して処理してください。文字列一括置換ではなく、マッチを走査して部分文字列を組み立てます。

```swift
private func maskedCloze(_ text: String, revealedIndices: Set<Int>) -> String {
    guard let regex = try? NSRegularExpression(pattern: #"\{\{(.+?)\}\}"#) else { return text }
    let ns = text as NSString
    var result = ""
    var cursor = 0
    for (i, m) in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).enumerated() {
        result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
        let word = ns.substring(with: m.range(at: 1))
        let hint = revealedIndices.contains(i) ? (word.first.map(String.init) ?? "") : ""
        result += "\(hint)[ ❓ 隠し ]"
        cursor = m.range.location + m.range.length
    }
    result += ns.substring(from: cursor)
    return result
}
```

あわせて、`[...]` パターンのサポートは落とすことを推奨します（UX-15）。

---

<a id="new-05"></a>

## NEW-05: 1セッションで全ストアをN回シリアライズ＋N回ディスク書き込みしている

**深刻度**: 🟠 High
**該当**: `src/Views/CourseDetailView.swift:87-93, 264-288`, `src/Services/DeckStore.swift:96-112`

学習セッション終了時、判定したカードを1枚ずつループで書き戻しています。

```swift
// CourseDetailView.swift:89
for card in sessionCards {
    updateSingleCardInCourse(card)      // ← 1枚ごとに
}
```

`updateSingleCardInCourse` は毎回:

1. `Course` 構造体を丸ごとコピー（全デッキ・全カードを含む値型）
2. `recalculateFilteredCards()` で全カードを2回フィルタ
3. `onSaveCourse` → `store.updateCourse` → **`saveToDisk()` で全ストア（全コース・全カード・全学習ログ）をJSONエンコードして書き込み**

20枚のセッションなら、**20回の全ストアシリアライズと20回のディスク書き込み**が、すべてメインスレッド上で同期実行されます。`DeckListView` 側の `sessionCards.forEach { store.updateCard(...) }` も同様です。

カード数千枚・学習ログ数万件の規模になると、セッション終了時に数秒単位のフリーズが発生します。`saveToDisk` は `.atomic` 指定なので、毎回テンポラリファイル作成→リネームも走ります。

### 推奨対応

- 一括更新APIを用意し、**保存は1回**にまとめる

```swift
public func applySessionResults(_ cards: [AnkiCard], courseId: UUID) {
    // メモリ上で全件反映してから
    saveToDisk()   // 保存は最後に1回
}
```

- 保存自体をデバウンス（例: 0.5秒の待機後にまとめて書き込み）し、`Task.detached` でメインスレッドから外す
- 中長期的には、全書き換えではなく差分更新できるストレージ（SwiftData / SQLite）へ移行する（ADR-0001の当初方針）

---

<a id="new-06"></a>

## NEW-06: APIキーが1文字入力するごとに Keychain へ書き込まれる／削除手段がない

**深刻度**: 🟠 High
**該当**: `src/Views/SettingsView.swift:43-46, 121-123`

SEC-01 への対応として `KeychainStore` が導入されたのは適切です。しかし保存タイミングに問題があります。

```swift
SecureField("OpenAI / Gemini API Key", text: $apiKeyInput)
    .onChange(of: apiKeyInput) { _, newValue in
        KeychainStore.save(key: "openAIApiKey", value: newValue)   // ← 1文字ごと
    }
```

`KeychainStore.save` は内部で `SecItemDelete` + `SecItemAdd` を実行します。50文字のAPIキーを入力すると **50回の削除＋追加**が走り、**キーの全ての途中経過（`s`, `sk`, `sk-`, `sk-p`, …）が順次Keychainに書き込まれます**。

加えて:

- `onAppear` で `apiKeyInput` に読み込んだ値を代入すると `onChange` が発火し、**同じ値の再書き込み**が起きます
- **キーを削除する手段がありません**。`KeychainStore.delete` は実装されていますが、`src/` からの呼び出しは0件です（テストからのみ）。フィールドを空にすると空文字が保存されるだけで、Keychain項目は残り続けます
- `kSecAttrAccessible` に `kSecAttrAccessibleAfterFirstUnlock` を指定していますが、これは**バックアップに含まれる**属性です。初回レビューで推奨した `...ThisDeviceOnly` にすると端末外への持ち出しを防げます

### 推奨対応

```swift
// 明示的な保存操作にする
SecureField("OpenAI / Gemini API Key", text: $apiKeyInput)
Button("APIキーを保存") {
    let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        KeychainStore.delete(key: "openAIApiKey")
    } else {
        KeychainStore.save(key: "openAIApiKey", value: trimmed)
    }
}
Button("保存済みのキーを削除", role: .destructive) {
    KeychainStore.delete(key: "openAIApiKey")
    apiKeyInput = ""
}
```

`KeychainStore.swift:25` の `kSecAttrAccessibleAfterFirstUnlock` は `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` に変更してください。

なお **AIカード自動生成機能は依然として未実装**です。初回レビューで述べた通り、使わない秘密情報は保管しないのが最も安全です。

---

<a id="new-07"></a>

## NEW-07: バックアップの「復元」が未実装なのに、UIは復元可能と説明している

**深刻度**: 🟠 High
**該当**: `src/Views/SettingsView.swift:53-75`, `src/Services/BackupService.swift:28`

新機能として `BackupService` が追加されましたが、**復元（import）はUIから到達できません**。

```
$ grep -rn "importBackupJSON" src
src/Services/BackupService.swift:28:    public static func importBackupJSON(...)   ← 定義のみ、呼び出し0件
```

一方でUIの文言は復元できると明言しています。

- セクション見出し: 「データバックアップ **& 復元** (FEAT-03)」
- フッター: 「全データをJSON形式でバックアップ**・復元できます**。」

ユーザーは「バックアップを取れば復元できる」と信じますが、実際には**復元手段が存在しません**。機種変更時に取り返しがつかない誤解です。

さらにプライバシー上の懸念があります。

```swift
UIPasteboard.general.string = json     // SettingsView.swift:60
```

**全学習データ（全コース・全カード・全学習ログ）が、確認なしでシステムのクリップボードにコピーされます。** iOSのクリップボードは他アプリから読み取り可能で、Universal Clipboard により**近くのMac/iPadへも自動的に同期**されます。学習内容には業務上の資格試験対策など機微な情報が含まれうるため、無言でのコピーは避けるべきです。

### 推奨対応

- 復元UIを実装する（テキスト貼り付け、または `.fileImporter` によるファイル読み込み）。復元は破壊的操作なので確認ダイアログを必須にしてください
- 実装が間に合わないなら、**見出しとフッターから「復元」の文言を削除**してください
- クリップボードではなく `ShareLink` / `.fileExporter` でのファイル書き出しに変更する。クリップボードを使う場合は事前に明示してユーザーの同意を得てください

```swift
ShareLink(item: backupJSONText, preview: SharePreview("kskAnki バックアップ"))
```

---

<a id="new-08"></a>

## NEW-08: 【リグレッション】表面の「🔊 朗読」ボタンが `question` / `cloze` カードから消えた

**深刻度**: 🟠 High（要件リグレッション）
**該当**: `src/Views/FlashcardView.swift:39-64, 246-278`

修正前の `FlashcardView` は、表面ヘッダーに全カードタイプ共通の「朗読」ボタンを持っていました。修正後、表面の音声再生は `.word` タイプの「発音を聴く」ボタンだけになっています。

```swift
case .word:
    Button(action: playFrontSpeech) { ... Text("発音を聴く") }   // ← ここだけ
case .question:
    Text(card.frontText)...                                      // ← 朗読ボタン無し
case .cloze:
    clozeFrontView                                               // ← 朗読ボタン無し
```

`REQUIREMENTS.md 3.7` は「**「🔊 朗読」ボタン: 表面・裏面の各ヘッダーに配置**」と定めています。表面ヘッダー（`FlashcardView.swift:39-64`）にはバッジ・カテゴリ・お気に入り星しかなく、要件を満たさなくなりました。

英語の例文問題（`question` タイプ）や穴埋め文の発音を聴きたいケースは自然に発生します。

### 推奨対応

表面ヘッダーに朗読ボタンを戻してください（`.word` の「発音を聴く」は残しても構いません）。

```swift
HStack {
    Text(card.frontType.badgeLabel) ...
    if let categoryPath = card.categoryPath { ... }
    Button(action: playFrontSpeech) {
        Label("朗読", systemImage: "speaker.wave.2.fill") ...
    }
    .buttonStyle(.plain)
    .accessibilityLabel("問題文の音声を再生")
    Spacer()
    ...
}
```

---

<a id="new-09"></a>

## NEW-09: 【リグレッション】コンテンツ一覧からカテゴリーバッジとタグ表示が消えた

**深刻度**: 🟠 High（要件リグレッション）
**該当**: `src/Views/CourseContentView.swift:111-131`

検索機能の追加（UI-08）自体は良い改善ですが、その過程で `cardRow` から表示項目が削られました。

修正前は `categoryPath`（「メイン ❯ サブ」）バッジとタグチップを表示していましたが、現在は `frontText` / お気に入り星 / `backText` のみです。

`REQUIREMENTS.md 3.8` は「コンテンツ一覧画面で**各カードのカテゴリーバッジ (`メイン ❯ サブ`) を表示**」と明記しています。

実際、`categoryPath` の参照箇所は `FlashcardView` の1箇所だけになりました。

```
$ grep -rn "categoryPath" src
src/Models/AnkiCard.swift:160:    public var categoryPath: String? { ... }
src/Views/FlashcardView.swift:50,51                                  ← ここだけ
```

カテゴリーは数百枚のカードを整理する主要な軸であり、一覧から消えると管理が困難になります。検索機能が入ったことでむしろ「カテゴリで探す」ニーズは高まっています。

### 推奨対応

`cardRow` にバッジ表示を戻してください。検索対象に `mainCategory` / `subCategory` を含めることもあわせて推奨します（現在は `frontText` / `backText` / `japaneseTranslation` / `tags` のみ）。

---

# 🟡 新規指摘（中程度）

<a id="new-10"></a>

## NEW-10: `updateAllCards` にカード重複バグが残存している（現状は到達不能）

**深刻度**: 🟡 Medium
**該当**: `src/Views/CourseDetailView.swift:290-301`

ARC-02 への対応で `updateSingleCardInCourse` / `deleteCardFromCourse` / `addCardsToCourse` は全デッキを走査する安全な実装になりました。しかし `updateAllCards` だけが修正されずに残っています。

```swift
private func updateAllCards(_ updatedCards: [AnkiCard]) {
    var updatedCourse = course
    if updatedCourse.decks.isEmpty { ... }
    else { updatedCourse.decks[0].cards = updatedCards }   // ← 全カードをデッキ0へ
}
```

この関数のバインディングは `get: { allCards }`（全デッキの平坦化）です。もし書き込みが発生すると、**デッキ1以降のカードがデッキ0にコピーされ、元の場所にも残るため全カードが重複**します。初回レビュー時の「デッキが消える」バグが「カードが増殖する」バグに変わった形です。

現在 `CourseContentView` はこの `@Binding` を読み取り専用でしか使っていないため**発火しません**。ただし将来誰かが `cards` へ書き込むと即座に顕在化します。

### 推奨対応

`CourseContentView` の `@Binding var cards` は実質不要なので `let cards: [AnkiCard]` に変更し、`updateAllCards` を削除してください。使われない危険なコードを残さないのが最善です。

---

<a id="new-11"></a>

## NEW-11: スワイプ操作のヒント文言が実装と食い違っている

**深刻度**: 🟡 Medium
**該当**: `src/Views/CardStudyView.swift:69`

UX-02 への対応として、上スワイプ（△）は**正しく廃止**され、横方向の軸ロック判定に変わりました（`CardStudyView.swift:136`）。良い判断です。

しかし画面に表示されるヒントが更新されていません。

```swift
Text("💡 ヒント: カードを右スワイプで ◯(正解)、左で ✕(不正解)、上で △(惜しい)")
```

**「上で △(惜しい)」は、もう存在しない操作です。** ユーザーは上スワイプを試し、何も起こらない（あるいはスクロールする）ことに戸惑います。

`swipeHintOverlay`（`:154-174`）からも △ の分岐は正しく削除済みなので、**この1行だけが取り残されています**。

### 推奨対応

```swift
Text("💡 ヒント: カードを右スワイプで ◯(正解)、左スワイプで ✕(不正解)。△(惜しい) は下のボタンから")
```

---

<a id="new-12"></a>

## NEW-12: 【リグレッション】カード切替時にメモの編集モードが解除されない

**深刻度**: 🟡 Medium
**該当**: `src/Views/FlashcardView.swift:239-242`

修正前は次のカードへ進む際に編集状態をリセットしていました。

```swift
// 修正前
.onChange(of: card.id) {
    noteText = card.userNotes
    isEditingNotes = false      // ← 削除された
    showHint = false
}
```

現在は `isEditingNotes` のリセットが失われています。そのため、メモを編集中にカードを進めると:

1. 入力途中のメモは `noteText = card.userNotes` で**上書きされて消える**（UX-10 未対応のまま）
2. **編集モードだけが開いたまま**次のカードに引き継がれる

キーボードが出たまま次のカードの解答が表示される状態になり、操作感が悪化しています。

### 推奨対応

`isEditingNotes = false` を戻したうえで、UX-10（未保存メモの消失）も併せて解消してください。カード切替時に未保存の変更があれば自動保存するのが最も素直です。

```swift
.onChange(of: card.id) { oldValue, _ in
    if isEditingNotes { onSaveNotes?(noteText) }   // 自動保存
    noteText = card.userNotes
    isEditingNotes = false
    showHint = false
}
```

---

<a id="new-13"></a>

## NEW-13: 【リグレッション】解答が空でも「解答・解説」ブロックが表示される

**深刻度**: 🟡 Medium
**該当**: `src/Views/FlashcardView.swift:113`

修正前は `if !card.backText.isEmpty` でガードしていましたが、現在は無条件に描画されます。

```swift
Text(card.backText)
    .font(.system(.title3, design: .rounded).weight(.bold))
```

`REQUIREMENTS.md 3.5` の「**未設定の項目は空白を残さず完全自動非表示**」に反します。和訳・例文・解説・類義語は正しく `isEmpty` ガードされているため、解答だけが例外になっています。

画像のみのカードや、和訳だけで答えを表現するカードで、見出しと空行が残ります。

### 推奨対応

```swift
if !card.backText.isEmpty {
    Text(card.backText)
        .font(.system(.title3, design: .rounded).weight(.bold))
}
```

---

<a id="new-14"></a>

## NEW-14: テストが開発者の実 `~/Documents` を汚染する（非密閉テスト）

**深刻度**: 🟡 Medium
**該当**: `src/Services/DeckStore.swift:80-84`, `tests/DeckStoreTests.swift`

`DeckStore` の保存先は `.documentDirectory` です。iOSではアプリコンテナ内ですが、**macOSではユーザーの実 `~/Documents` フォルダ**を指します。実測で確認しました。

```
$ swiftc -o probe probe.swift && ./probe
completeFileProtection write: SUCCESS -> /Users/ksk/Documents/kskAnki_fp_probe.json
```

`DeckStoreTests` は `DeckStore()` を生成して `saveToDisk()` を呼ぶため、**テストを実行すると `~/Documents/kskAnki_store.json` が作られます**。`ImageStore` を使うテストを足せば `~/Documents/CardImages/` も作られます。

さらに問題なのは**テストの非密閉性**です。

- `DeckStore()` は起動時に `loadFromDisk()` するため、**前回のテスト実行が残したファイルを読み込みます**
- テスト末尾の後始末は `newStore.deleteCourse(testCourse.id)` だけで、`studyLogs` に積んだ2件のログとファイル自体は残ります
- 実行順序や実行回数によって結果が変わりうる構成です

（なお `.completeFileProtection` は macOS では無視されるだけでエラーにならないことも上記の実測で確認済みです。CIでの `saveToDisk()` は成功します。）

### 推奨対応

保存先を注入可能にし、テストは一時ディレクトリを使ってください。

```swift
public init(folders: [CourseFolder] = [], courses: [Course] = [], storageURL: URL? = nil) {
    self.saveFileURL = storageURL ?? DeckStore.defaultStorageURL
    ...
}

// テスト側
let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
let store = DeckStore(storageURL: tempDir.appendingPathComponent("store.json"))
addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
```

これは NEW-01（テストが実行されていない）を直すと即座に問題化するので、あわせて対応してください。

---

<a id="new-15"></a>

## NEW-15: 「本日の学習枚数」がログ件数であり、枚数ではない

**深刻度**: 🟡 Medium
**該当**: `src/Services/DeckStore.swift:41-44`, `src/Views/StudyStatsView.swift:26`

```swift
public var todayStudiedCardsCount: Int {
    studyLogs.filter { calendar.isDateInToday($0.studiedAt) }.count
}
```

UI表記は「**\(todayStudiedCardsCount) / \(dailyGoalCardsCount) 枚**」ですが、実体は**学習イベントの件数**です。同じカードを1日に3回判定すると「3枚」と表示されます。

苦手カードを繰り返し復習するのは推奨される学習法なので、**繰り返すほど目標達成が水増しされます**。日次目標としての意味が失われます。

`StudyStatsView` の7日間グラフ（`:26`）も同じ数え方です。

### 推奨対応

枚数として数えるならカードIDでユニーク化してください。

```swift
public var todayStudiedCardsCount: Int {
    Set(studyLogs.filter { calendar.isDateInToday($0.studiedAt) }.map(\.cardId)).count
}
```

イベント数を見せたいなら、ラベルを「回」に変える（統計画面の「累計学習セッション … 回」は正しい表記です）か、「枚（うち延べN回）」と併記する方法もあります。

---

<a id="new-16"></a>

## NEW-16: `filterCards(currentDate:)` が一部のケースにしか効かない

**深刻度**: 🟡 Medium
**該当**: `src/Models/StudyFilter.swift:77-118`

SRS-01 の対応で `currentDate` パラメータが追加されたのは、テスタビリティの面で良い設計です。しかし**実際に使われているのは `.dueToday` と `.overdue` の2ケースだけ**です。

```swift
case .studiedToday:
    filtered = cards.filter { $0.isStudiedToday }        // ← 内部で Date() を直接参照
```

`isStudiedToday` / `isStudiedYesterday` / `isStudiedWithinOneWeek` / `isMaintenanceNeeded` はいずれも `AnkiCard` 内部で `Date()` を呼んでおり、注入した `currentDate` を無視します。

- `filterCards(cards, currentDate: 昨日)` のようなテストを書いても、日付系フィルタは常に「実行時の今日」で判定されます
- 引数があることで「時刻を制御できる」と誤解を招きます

### 推奨対応

日付依存の判定を `AnkiCard` のプロパティから関数に変え、基準日を受け取れるようにしてください。

```swift
public func isStudied(on day: Date, calendar: Calendar = .current) -> Bool { ... }
public func isStudiedWithin(days: Int, from reference: Date, calendar: Calendar = .current) -> Bool { ... }
```

SRS-07（1日の区切りを午前4時にする）も未対応のままなので、この機会に日付判定を1箇所に集約すると両方まとめて解決できます。

---

<a id="new-17"></a>

## NEW-17: `studyLogs` が無制限に増加し、毎回の保存で全件シリアライズされる

**深刻度**: 🟡 Medium
**該当**: `src/Services/DeckStore.swift:35, 97-107`

`studyLogs` には削除・集約・上限のロジックがありません。1日20枚の学習を1年続ければ約7,300件、数年で数万件に達します。

これが `DeckStoreSnapshot` に含まれ、**カードを1枚更新するたびに全件がJSONエンコードされてディスクに書かれます**（NEW-05 と複合すると、1セッションで数十回）。

また、`StudyLog` は `id: UUID` を持ちますが、この `id` はどこからも参照されていません。1件あたりのJSONサイズを不必要に増やしています。

### 推奨対応

- 学習ログを別ファイルに分離し、カード更新時に巻き込まれないようにする
- 一定期間（例: 過去90日）より古いログは日単位の集計に畳む

```swift
struct DailyStudySummary: Codable { let day: Date; let correct: Int; let doubtful: Int; let incorrect: Int; let uniqueCards: Int }
```

ストリーク計算も統計グラフも日単位の集計で十分なので、生ログを永久保持する必要はありません。

---

# 🔵 新規指摘（軽微）

<a id="new-18"></a>

## NEW-18: 削除済みコースを開こうとすると操作できない空シートが出る

**深刻度**: 🔵 Low
**該当**: `src/Views/DeckListView.swift:128-134`

ARC-06 への対応として、シート表示時にストアから最新のコースを引き直す形になりました。方向性は正しい修正です。

```swift
.sheet(item: $selectedCourseForDetail) { course in
    if let latestCourse = store.courses.first(where: { $0.id == course.id }) {
        CourseDetailView(course: latestCourse) { ... }
    }
    // else が無い
}
```

コースが削除済みだと `if let` が失敗し、**中身が空のシートが提示されます**。ナビゲーションバーも「閉じる」ボタンもないため、下スワイプでしか閉じられません。

### 推奨対応

```swift
} else {
    ContentUnavailableView("コースが見つかりません",
                           systemImage: "questionmark.folder",
                           description: Text("このコースは削除された可能性があります。"))
}
```

もしくは、`selectedCourseForDetail` に `Course` ではなく `Course.ID` を持たせ、削除時に `nil` を代入して自動的に閉じる設計にしてください。

---

<a id="new-19"></a>

## NEW-19: 到達不能なコードが増えている

**深刻度**: 🔵 Low

全文検索で、定義されているが呼び出しが0件の公開APIを確認しました。

| シンボル | 場所 | 状況 |
|---|---|---|
| `BackupService.importBackupJSON` | `BackupService.swift:28` | UIから到達不能（→ [NEW-07](#new-07)） |
| `KeychainStore.delete` | `KeychainStore.swift:52` | `src/` からの呼び出し0件（→ [NEW-06](#new-06)） |
| `AudioService.playAudio` | `AudioService.swift:41` | `FlashcardView` から音声URL再生分岐が削除され、完全な死にコードに |
| `AnkiCard.frontAudioURL` / `backAudioURL` | `AnkiCard.swift:70-71` | 読み書きするコードが1箇所も無くなった |
| `Course.themeColorHex` / `CourseFolder.themeColorHex` | 各モデル | 描画に使われない（UX-14 未対応） |
| `CreateCourseView.availableColors` | `CreateCourseView.swift:25` | 宣言のみ、UI無し（UX-14 未対応） |

特に **`frontAudioURL` / `backAudioURL` は状況が後退**しています。初回レビュー時点では `FlashcardView` に `AVPlayer` 再生の分岐が存在しましたが、リファクタリングで削除され、`REQUIREMENTS.md 3.7`「添付音声URLがある場合は `AVPlayer` で音声再生」を満たすコードが**完全に消滅**しました（SEC-04 が悪化）。

### 推奨対応

各機能について「実装する」か「モデルごと削除する」かを決めてください。中途半端に残ったAPIは、後から SEC-02（URLスキーム未検証）のような問題を持ち込む温床になります。

---

# 未対応のまま残っている初回指摘

以下は今回のレビューで**変更が確認できなかった**ものです。詳細は初回レビュー各ドキュメントを参照してください。

| ID | 深刻度 | 概要 | 補足 |
|---|---|---|---|
| [BLK-01](01-blockers.md#blk-01) | 🔴 | iOSアプリターゲット不在 | → [NEW-03](#new-03) |
| [SRS-07](03-srs-algorithm.md#srs-07) | 🟡 | 1日の区切りが午前0時（Ankiは午前4時） | ストリーク実装が入った今こそ重要 |
| [SRS-08](03-srs-algorithm.md#srs-08) | 🔵 | `hasEverBeenTriangle` の冗長条件 | |
| [UX-09](04-ui-ux-accessibility.md#ux-09) | 🔵 | 進捗バーが1枚目で100%表示 | `ProgressView(value: Double(currentIndex))` に変更するだけ |
| [UX-10](04-ui-ux-accessibility.md#ux-10) | 🟡 | 未保存メモが消える | → [NEW-12](#new-12) で悪化 |
| [UX-11](04-ui-ux-accessibility.md#ux-11) | 🟡 | コース削除に確認ダイアログがない | 永続化が入り、実際にデータが消えるようになった分、危険度が上昇 |
| [UX-12](04-ui-ux-accessibility.md#ux-12) | 🟡 | 「未分類」フォルダを絞り込めない | `DeckListView.swift:17` のコメントも実装と不一致のまま |
| [UX-13](04-ui-ux-accessibility.md#ux-13) | 🟡 | ページ番号がクランプされない | |
| [UX-14](04-ui-ux-accessibility.md#ux-14) | 🟡 | テーマカラー未使用・日付未表示 | `Color.blue` 固定のまま |
| [UX-15](04-ui-ux-accessibility.md#ux-15) | 🟡 | 穴埋めの `[...]` が誤爆 | 実測で再現（→ [NEW-04](#new-04)） |
| [UX-16](04-ui-ux-accessibility.md#ux-16) | 🔵 | 全空欄が同時にヒント開示 | 誤った文字で開示されるため悪化 |
| [SEC-02](05-security-and-privacy.md#sec-02) | 🟡 | URLスキーム未検証・ATS | `AudioService` は完全に未変更 |
| [SEC-03](05-security-and-privacy.md#sec-03) | 🟡 | `AVAudioSession` を解放しない・消音無視 | 同上 |
| [SEC-04](05-security-and-privacy.md#sec-04) | 🔵 | 音声URLのデッドフィールド | 悪化（→ [NEW-19](#new-19)） |
| [SEC-05](05-security-and-privacy.md#sec-05) | 🔵 | Privacy Manifest | BLK-01未対応のため着手不能 |
| [QA-03](06-code-quality-and-testing.md#qa-03) | 🟡 | `.gitignore` にSwift/Xcodeエントリが無い | **完全に未対応**。下記参照 |
| [QA-04](06-code-quality-and-testing.md#qa-04) | 🟡 | `Array(Set(...))` で画像順序が崩れる | `AddCardView:312`, `EditCardView:276` に残存 |
| [QA-05](06-code-quality-and-testing.md#qa-05) | 🟡 | 言語自動判定が粗い | `AudioService` 未変更 |
| [QA-07](06-code-quality-and-testing.md#qa-07) | 🔵 | i18n未対応 | |

### QA-03 は初回コミット前に必ず対応してください

このリポジトリには**まだ1つもコミットがありません**（`git log` でコミット0件）。`.gitignore` は Node/Python 向けのままで、Swift関連の記述がありません。

```
$ git status --short
?? .build/          ← 数千のビルド成果物が追跡対象
```

このまま `git add -A` すると `.build/` 配下がすべてコミットされます。

```gitignore
# Swift / SPM
.build/
.swiftpm/

# Xcode
DerivedData/
*.xcuserstate
xcuserdata/
```

---

## 次のアクション（優先順）

1. **`#if canImport(XCTest)` を外し、テストが実際に走る状態にする**（[NEW-01](#new-01)）。CIに0件実行の検出も追加する。ここが通らないと、以降のすべての修正が検証不能です
2. **学習ログの記録経路を統一する**（[NEW-02](#new-02)）。ストリーク・統計ダッシュボードは実装済みなのに、データが流れていないだけです。修正コストに対して効果が最も大きい箇所です
3. **Xcodeをインストールし、iOSアプリターゲットを作る**（[NEW-03](#new-03) / BLK-01）。`exclude: ["App"]` を外し、エントリポイントを型チェックの対象に戻す
4. **`.gitignore` を整備してから初回コミットする**（QA-03）
5. リグレッション3件を戻す（[NEW-04](#new-04) 誤ヒント / [NEW-08](#new-08) 朗読ボタン / [NEW-09](#new-09) カテゴリーバッジ）
6. セッション保存のバッチ化（[NEW-05](#new-05)）、Keychainの保存タイミング（[NEW-06](#new-06)）、バックアップ復元（[NEW-07](#new-07)）

`AudioService` は今回の対応で1行も変更されておらず、SEC-02 / SEC-03 / QA-05 がまとめて残っています。ファイル単位で見落とされた可能性が高いので、次回の対応時に確認してください。
