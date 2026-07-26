# 06. コード品質 & テスト

---

<a id="qa-01"></a>

## QA-01: テストフレームワークを使っておらず、テストが1件も実行されていない

**深刻度**: 🟠 High
**該当**: `tests/SpacedRepetitionTests.swift`

```swift
import Foundation
@testable import kskAnkiCore

public struct SpacedRepetitionVerifier {
    public static func verifyAll() {
        ...
        assert(card.consecutiveCorrectCount == 4, "4回連続正解カウントが不一致")
    }
}
```

問題が3重になっています。

1. **`XCTest` も `Testing` も import していない** — `@Test` / `XCTestCase` が無いため、`swift test` はこのコードを**テストとして認識しません**。`verifyAll()` を呼ぶ人もいないので、実行されることは永久にありません
2. **`swift test` 自体がリンクエラーで失敗する**（[BLK-02](01-blockers.md#blk-02)）。仮に正しく書かれていても走りません
3. **`assert` はリリースビルドで消去される** — `-Ounchecked` / Release 構成では条件式ごと除去されます。テストの停止条件としては不適切です

結果、このプロジェクトの **テストカバレッジは実質0%** です。

特に惜しいのは、テストしやすい純粋ロジックが揃っていることです。以下はすべてUIから独立しており、数十行のテストで品質を固定できます。

| 対象 | 場所 | テストすべき内容 |
|---|---|---|
| `SpacedRepetitionScheduler.processReview` | `SpacedRepetition.swift:9` | ◯△✕ ごとの `reps` / `interval` / `EF` / `dueDate` 遷移。`currentDate` 注入済みで日付テストも容易 |
| `StudyFilterConfig.filterCards` | `StudyFilter.swift:71` | 13条件 × 境界値。`batchSize` の切り出し |
| cloze パーサ | `FlashcardView.swift:333` | `{{}}` / `[]` / 複数空欄 / 記号衝突（[UX-15](04-ui-ux-accessibility.md#ux-15)） |
| CSV パーサ | `AddCardView.swift:332` | 列数不足・引用符・空行（QA-02） |
| `AnkiCard` の各種判定プロパティ | `AnkiCard.swift:172-236` | `isUnlearned` の意味（[SRS-04](03-srs-algorithm.md#srs-04)）、日付境界 |

本レビューで指摘した SRS 系のバグ（SRS-02〜05）は、いずれも**素直な単体テストを1本書けば発見できるもの**です。

### 推奨対応

Swift 6 なので `swift-testing` を推奨します（Xcode 16+ に同梱、`Package.swift` への追加依存は不要）。

```swift
import Testing
@testable import kskAnkiCore

@Suite("間隔反復スケジューラ")
struct SpacedRepetitionTests {

    @Test("◯を4回連続で付けると習得済みになる")
    func fourConsecutiveCorrect() {
        let scheduler = SpacedRepetitionScheduler()
        var card = AnkiCard(frontText: "Q", backText: "A")
        var day = Date()
        for _ in 1...4 {
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
            card = scheduler.processReview(card: card, rating: .correct, currentDate: day)
        }
        #expect(card.consecutiveCorrectCount == 4)
        #expect(card.isMasteredFourTimes)
    }

    @Test("easeFactor に上限があること")           // SRS-02 の回帰テスト
    func easeFactorIsCapped() {
        let scheduler = SpacedRepetitionScheduler()
        var card = AnkiCard(frontText: "Q", backText: "A")
        for _ in 1...100 { card = scheduler.processReview(card: card, rating: .correct) }
        #expect(card.easeFactor <= 2.5)
    }

    @Test("△ では復習間隔が伸びないこと")           // SRS-03 の回帰テスト
    func doubtfulDoesNotExtendInterval() {
        let scheduler = SpacedRepetitionScheduler()
        var card = AnkiCard(frontText: "Q", backText: "A", reps: 3, intervalDays: 20)
        card = scheduler.processReview(card: card, rating: .doubtful)
        #expect(card.intervalDays < 20)
    }
}
```

---

<a id="qa-02"></a>

## QA-02: CSVパーサが実用に耐えず、失敗しても何も伝えない

**深刻度**: 🟡 Medium
**該当**: `src/Views/AddCardView.swift:332-377`

```swift
let parts = trimmed.components(separatedBy: ",")
```

RFC 4180 のCSVを単純な `components(separatedBy: ",")` で分割しています。以下がすべて壊れます。

| 入力 | 期待 | 実際 |
|---|---|---|
| `"Apple, Inc.", アップル社` | 表面=`Apple, Inc.` | 表面=`"Apple`, 裏面=`Inc."`, メインカテゴリ=`アップル社` |
| `Deadlock, デッドロック, IT, OS, 重要, 頻出` | タグ=`[重要, 頻出]` | 動作するが、意図せず6列目以降が全部タグになる（`parts[4...]`, :355） |
| `front,back` の1列のみ | エラー表示 | **無言でスキップ**（:341 の `if parts.count >= 2`） |
| 全行が不正 | エラー表示 | **無言で何も起きない**（:372 の `if !newCards.isEmpty` で分岐外れ、メッセージも更新されない） |

さらに:

- **ヘッダー行のスキップがない** — `表面,裏面,...` という見出し行がそのままカードになります
- **列が固定5種のみ** — `frontType`（問題/単語/穴埋め）、解説1〜3、和訳、例文といったモデルの主要フィールドを取り込めません。手動追加では入力できるのに一括取り込みでは落ちるため、大量投入したいユーザーほど使えません
- **`frontType` が常に `.question`**（:360-366 で指定なし）— 単語帳を一括投入しても全て「問題」スタイルになります
- **重複検出がない** — 同じCSVを2回貼れば全カードが二重登録されます

`REQUIREMENTS.md 3.8` は「CSV一括取り込み（表面, 裏面, メインカテゴリー, サブカテゴリー, タグ 形式）」と定めているので列仕様自体は要件通りですが、堅牢性とフィードバックが不足しています。

### 推奨対応

- パーサを `AddCardView` から**独立した型へ切り出す**（テスト可能にする — QA-01）

```swift
struct CSVCardParser {
    struct Result { let cards: [AnkiCard]; let skippedLines: [(line: Int, reason: String)] }
    func parse(_ text: String) -> Result
}
```

- 引用符で囲まれたフィールドとエスケープ（`""`）に対応する
- 失敗行を件数と理由付きでUIに返す（現在の `importedCountMessage` を成功/失敗の両方に使う）
- ヘッダー行の自動判別、`frontType` 列の追加を検討する

なお `importedCountMessage` は手動追加（:328）とCSV取り込み（:374）で共有されており、タブを切り替えると前の操作のメッセージが残ります。用途を分けてください。

---

<a id="qa-03"></a>

## QA-03: `.gitignore` が Swift/Xcode に未対応 — ビルド成果物がコミットされる

**深刻度**: 🟡 Medium
**該当**: `.gitignore`

現在の `.gitignore` は Node.js / Python / 汎用ビルド出力 (`dist/`, `build/`) のエントリで構成されており、**Swift 関連の記述が1行もありません**。

一方、リポジトリの状態は:

- `git log` にコミットが1件も存在しない（初回コミット前）
- `git status` で `.build/` が未追跡として表示される
- `.build/` 配下には **数千のビルド成果物**（`.swiftmodule`, `.o`, `build.db`, ModuleCache）が既に生成済み

このまま `git add -A` すると、**ビルドキャッシュがすべてリポジトリに入ります**。リポジトリサイズが膨れ、以後のdiffがノイズだらけになります。

### 推奨対応

初回コミット前に追記してください。

```gitignore
# Swift / SPM
.build/
.swiftpm/
Package.resolved        # アプリ実行ファイルの場合はコミットするほうが望ましい（要方針決定）

# Xcode
DerivedData/
*.xcuserstate
xcuserdata/
*.xcscmblueprint
*.xccheckout
```

`.scratch/` については、開発時のspec置き場として意図的に管理している（`README.md` に構成が明記されている）ようなので、コミット対象で問題ありません。判断を明文化しておくと迷いません。

---

<a id="qa-04"></a>

## QA-04: `Array(Set(...))` により画像の並び順が毎回シャッフルされる

**深刻度**: 🟡 Medium
**該当**: `src/Views/AddCardView.swift:288-289`, `src/Views/EditCardView.swift:252-253`

```swift
let finalFrontImgs = Array(Set(frontImageURLs + textFrontImgs))
```

重複除去のために `Set` を経由していますが、**`Set` は順序を保持しません**。Swiftの `Set` のイテレーション順はハッシュシードに依存し、プロセスごとに変わります。

そのため:

- 図表を「①→②→③」の順に登録しても、保存するたびに順番が入れ替わります
- カードを編集して保存し直すたびに、画像の並びが変わります
- 学習フローで「1枚目に問題図、2枚目に解答図」といった構成が破綻します

学習教材において図版の順序は意味を持つ情報です。

### 推奨対応

順序を保つ重複除去を使ってください。

```swift
extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

let finalFrontImgs = (frontImageURLs + textFrontImgs).uniqued()
```

---

<a id="qa-05"></a>

## QA-05: 言語自動判定のヒューリスティックが誤判定しやすい

**深刻度**: 🟡 Medium
**該当**: `src/Services/AudioService.swift:48-58`

```swift
let latinCount = text.unicodeScalars.filter { ... A-Z, a-z ... }.count
if Double(latinCount) / Double(max(1, text.count)) > 0.3 {
    return "en-US"
} else {
    return "ja-JP"
}
```

3つの問題があります。

1. **分子と分母の単位が違う** — 分子は `unicodeScalars`（Unicodeスカラー）、分母は `text.count`（書記素クラスタ）を数えています。絵文字や結合文字を含むテキストで比率が歪みます。サンプルデータには絵文字を含むカードが存在します。
2. **閾値0.3が低すぎる** — 日本語中心の文でも英単語が3割あれば英語音声になります。本プロジェクトの主要コンテンツである技術系カード（例: 「Cloud Run ジョブ」「GKEの運用モードで…Autopilotモード」）は、**ラテン文字比率が0.3を軽く超えるのに日本語文**です。日本語を英語音声で読み上げると、ほぼ意味不明な発音になります。
3. **英語と日本語の2択しかない** — `EditCardView.swift:204` はスペイン語 (`es-ES`) を選択肢に含めており、サンプルデータにもスペイン語コースがありますが、自動判定では**絶対にスペイン語にはなりません**。`speechLanguage` を明示設定しない限り、`Hola` は英語音声で読まれます。

加えて、`AVSpeechSynthesisVoice(language:)` は該当音声が未インストールなら `nil` を返し、`utterance.voice = nil` はシステム既定言語へ黙って切り替わります（`AudioService.swift:28`）。ユーザーには原因が分かりません。

### 推奨対応

Foundation の言語判定を使ってください。

```swift
import NaturalLanguage

private func detectLanguage(for text: String) -> String {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    switch recognizer.dominantLanguage {
    case .japanese: return "ja-JP"
    case .spanish:  return "es-ES"
    case .english:  return "en-US"
    default:        return "en-US"
    }
}
```

より確実なのは、**カード作成時に `speechLanguage` を必ず設定させる**ことです。`AddCardView` には読み上げ言語のピッカーがありません（`EditCardView` にはあります）。コース単位の既定言語を持たせると入力負荷も下がります。

---

<a id="qa-06"></a>

## QA-06: 巨大なビュー / データの直書き / コード重複

**深刻度**: 🟡 Medium

| ファイル | 行数 | 問題 |
|---|---|---|
| `src/Views/FlashcardView.swift` | 565 | 1つの `View` に表面3パターン描画・clozeパーサ・画像ギャラリー・メモ編集・音声再生がすべて同居 |
| `src/Views/DeckListView.swift` | 490 | ストリーク表示・フォルダチップ・ソート・ページャ・コースカード・デッキ行 |
| `src/Services/DeckStore.swift` | 406 | **うち340行（84%）がサンプルデータのハードコード** |
| `src/Views/AddCardView.swift` / `EditCardView.swift` | 378 / 273 | **画像セクション約90行 × 2箇所 × 2ファイル がほぼ完全な重複** |

具体的な影響:

- **cloze パーサがView内のprivate関数** (`FlashcardView.swift:333`) — ロジックがUIに埋まっており、単体テストが書けません（QA-01）
- **Add/Edit の重複** — UX-03（PhotosPicker実装）を直す際、同じ修正を**4箇所**に入れる必要があります。修正漏れが発生する典型的な構造です
- **サンプルデータの直書き** — `DeckStore` を読むとき340行をスクロールしないと実装に辿り着きません（ARC-03と同根）

### 推奨対応

- `ClozeParser` を `src/Models/` へ切り出す（純粋関数、テスト可能に）
- `CardImageSection` を共通Viewとして切り出し、Add/Edit の4箇所を1つに集約する
- サンプルデータを `SampleData.swift` へ移す（ARC-03）
- `FlashcardView` を `CardFrontView` / `CardBackView` / `UserNotesSection` に分割する

これらはいずれも機能を変えないリファクタリングなので、テスト（QA-01）を先に入れておくと安全に進められます。

---

<a id="qa-07"></a>

## QA-07: 国際化 (i18n) 対応がなく、UI文言の言語も混在している

**深刻度**: 🔵 Low
**該当**: `src/Views/` 全体

すべてのUI文字列が日本語リテラルの直書きです。`String(localized:)` も String Catalog (`.xcstrings`) も使われていません。

- 将来の多言語展開時に、全ビューを書き換える必要があります
- 日付表示も `Date` の直接比較のみで、ロケール対応の書式化（`formatted(.relative(...))` 等）を使っていません

また、文言の言語が一貫していません。

| 箇所 | 表記 |
|---|---|
| `FlashcardView.swift:108` | `ANSWER`（英語） |
| `AnkiCard.swift:20-24` | `QUESTION` / `WORD` / `CLOZE (穴埋め)`（英語・混在） |
| `FlashcardView.swift:150` | `例文 (Example)`（併記） |
| `FlashcardView.swift:503` | `マイメモ`（日本語） |

デザイン上の意図（英語バッジをアクセントに使う）である可能性はありますが、`CLOZE (穴埋め)` のように同一enum内で表記ルールが揺れているのは意図的とは考えにくいです。

### 推奨対応

日本語専用アプリとして進めるなら i18n は後回しで構いませんが、**バッジの表記ルールだけは統一**してください。将来対応する場合は String Catalog（Xcode 15+）が最も低コストです。

---

<a id="qa-08"></a>

## QA-08: 操作結果のフィードバックとエラー処理が不足している

**深刻度**: 🔵 Low

ユーザーに結果が伝わらない箇所が複数あります。

| 箇所 | 現状 |
|---|---|
| `AddCardView.swift:372` CSV取り込み | 0件の場合、成功メッセージも失敗メッセージも出ない。ボタンを押しても**画面が何も変わらない** |
| `AudioService.swift:33-34` 音声セッション | `try?` で全エラーを握り潰す。音が出ない原因が分からない |
| `AudioService.swift:42` 音声再生 | URLが不正なら `return` するだけ。無反応 |
| `FlashcardView.swift:466` 画像読み込み失敗 | 汎用アイコンのみ。URLが悪いのか通信が悪いのか判別不能 |
| `CourseDetailView.swift:209` 学習開始 | 0枚なら `guard` で無反応（ボタンは `disabled` されているので実害は小さい） |

「押したのに何も起こらない」はユーザーが最も混乱する挙動です。特にCSV取り込みは、貼り付けたテキストの形式が悪いことに気づけません。

### 推奨対応

成功・失敗の双方を必ず伝えてください。

```swift
if newCards.isEmpty {
    importedCountMessage = "取り込めるカードがありませんでした。「表面, 裏面」の2列以上が必要です。"
    importResultIsError = true
} else {
    importedCountMessage = "\(newCards.count) 枚のカードを取り込みました。"
    importResultIsError = false
}
```

音声・画像については、`try?` を握り潰さず `Logger`（OSLog）に記録し、ユーザー向けには簡潔なメッセージを出す方針を推奨します。
