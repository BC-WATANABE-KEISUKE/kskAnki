# 02. アーキテクチャ & データ設計

---

<a id="arc-01"></a>

## ARC-01: 「コース配下のデッキ」と「マイ単語帳」が完全に分断された二重世界になっている

**深刻度**: 🟠 High
**該当**: `src/Services/DeckStore.swift:7-9, 52-64`, `src/Views/DeckListView.swift:222-229`

`DeckStore` は3つの独立した配列を持っています。

```swift
public var folders: [CourseFolder] = []
public var courses:  [Course]      = []   // Course.decks[].cards[] にカードを内包
public var decks:    [AnkiDeck]    = []   // ↑とは無関係な、もう一つのカード置き場
```

`REQUIREMENTS.md 2.1` が定義する階層は **フォルダ → コース → デッキ → カード** の単一ツリーです。しかし実装では `store.decks` という第2の系統が並立しており、トップ画面はこの両方を同時に表示しています（`DeckListView.swift:222`「マイ単語帳 (すべてのデッキ)」セクション）。

この結果、次の不整合が生じます。

- `DeckStore.addCard(_:toDeckId:)` / `updateCard(_:inDeckId:)` は `store.decks` のみを操作し、**コース配下のカードには一切届きません**
- コースで作ったカードは「マイ単語帳」に現れず、その逆も同様
- ユーザーには2つのリストが同じ見た目で並ぶため、どちらに追加されたのか判別できません
- 「該当: N枚」などの集計が、どちらの世界を指しているのか一貫しません

要件書にも `store.decks` に相当する概念は存在せず、**サンプルデータ表示のためだけに残った構造が本番UIに露出している**状態と見られます。

### 推奨対応

いずれかに統一してください。推奨は前者です。

1. **`store.decks` を廃止**し、全カードを `courses[].decks[].cards[]` に一元化する。トップ画面の「マイ単語帳」セクションは削除するか、「全コース横断のデッキ一覧」として `courses.flatMap(\.decks)` から導出する
2. 逆に `decks` を唯一の実体とし、`Course` は `deckIds: [UUID]` の参照だけを持つ正規化構造にする

---

<a id="arc-02"></a>

## ARC-02: カードを1枚編集すると、コース内の2つ目以降のデッキが消滅する

**深刻度**: 🔴 Blocker級のデータ損失（実害はBLK-03により顕在化していないだけ）
**該当**: `src/Views/CourseDetailView.swift:223-233`

```swift
private func updateAllCards(_ updatedCards: [AnkiCard]) {
    if var firstDeck = course.decks.first {
        firstDeck.cards = updatedCards
        course.decks = [firstDeck]        // ← 2つ目以降のデッキを丸ごと破棄
    } else {
        ...
    }
}
```

`allCards` は `course.decks.flatMap { $0.cards }` で全デッキのカードを平坦化していますが（`CourseDetailView.swift:28`）、書き戻す際は **先頭デッキ1つに全カードを詰め込み、残りのデッキを配列ごと消去**しています。

`Course.decks` は `[AnkiDeck]` であり、要件2.1もコース配下に複数デッキを想定しています。したがって **2つ以上のデッキを持つコースでカードを1枚でも編集・追加・削除・お気に入り切替すると、2つ目以降のデッキ（名前・説明・作成日を含む）が永久に失われます。**

現在サンプルデータの全コースがデッキ1つなので表面化していませんが、複数デッキを作れるようになった瞬間に発火します。

この関数は `updateSingleCardInCourse` / `deleteCardFromCourse` / `addCardsToCourse` すべての合流点なので、影響範囲はコンテンツ管理機能の全体です。

### 推奨対応

カードは所属デッキIDを保持し、デッキ単位で更新してください。

```swift
// AnkiCard に deckId: UUID を追加するか、
// あるいは (deckIndex, cardIndex) を解決して該当デッキだけを更新する
private func updateSingleCardInCourse(_ updatedCard: AnkiCard) {
    for deckIdx in course.decks.indices {
        if let cardIdx = course.decks[deckIdx].cards.firstIndex(where: { $0.id == updatedCard.id }) {
            course.decks[deckIdx].cards[cardIdx] = updatedCard
            course.updatedAt = Date()
            onSaveCourse(course)
            return
        }
    }
}
```

---

<a id="arc-03"></a>

## ARC-03: `DeckStore.init` がサンプルデータを無条件に復活させる

**深刻度**: 🟠 High
**該当**: `src/Services/DeckStore.swift:16-20`

```swift
public init(folders: [CourseFolder] = [], courses: [Course] = [], decks: [AnkiDeck] = []) {
    self.folders = folders.isEmpty ? DeckStore.sampleFolders : folders
    self.courses = courses.isEmpty ? DeckStore.sampleCourses(folders: self.folders) : courses
    self.decks   = decks.isEmpty   ? DeckStore.sampleDecks   : decks
}
```

「空配列ならサンプルデータで埋める」というロジックがイニシャライザに埋め込まれています。永続化を実装した後、これは次の不具合になります。

- ユーザーが全コースを削除する → 次回起動時にサンプル6コースが復活する
- ユーザーが「削除できないコースがある」と感じる（削除→再起動で戻る）
- テストで「空のストア」を作れない（常にサンプルが入る）

また、サンプルデータ生成コード（`DeckStore.swift:66-405`）が **340行、ファイル全体の84%** を占めており、本来の責務であるデータ管理ロジック（65行）を埋没させています。

### 推奨対応

- サンプル投入は初回起動時のみの明示的なシード処理として分離する（`hasSeededInitialData` フラグを `UserDefaults` に持つ）
- サンプルデータは `DeckStore` から `SampleData.swift`（またはPreview専用ターゲット）へ切り出す
- `DeckStore()` は空で生成できるようにする

---

<a id="arc-04"></a>

## ARC-04: ストリーク・本日の学習枚数がハードコードされた偽データ

**深刻度**: 🟠 High
**該当**: `src/Services/DeckStore.swift:12-14`, `src/Views/DeckListView.swift:136, 154, 159`

```swift
public var streakDaysCount: Int = 3           // ← 定数
public var todayStudiedCardsCount: Int = 12   // ← 定数
public var dailyGoalCardsCount: Int = 20      // ← 定数
```

これらはトップ画面の最上部に、実データと同じ見た目で表示されます。

- 🔥 **3日連続学習中！**
- 本日の目標 **12 / 20 枚** ＋ プログレスバー

しかし全文検索の結果、**これらの値を更新するコードは1行も存在しません**。インストール直後の初回起動でも「3日連続」「12枚学習済み」と表示され、その後どれだけ学習しても永久に変わりません。

`.scratch/expert-improvements/spec.md` は機能4として「連続学習日数カウント」「本日の学習枚数達成メーター」を要求しており、**仕様に対して未実装のまま、UIだけが先に置かれている**状態です。

ストリークは学習継続の動機付けとして機能する重要なゲーミフィケーション要素です。偽の数値はむしろユーザーの信頼を損ないます。

### 推奨対応

学習ログを永続化し、そこから算出してください。

```swift
// 学習イベントの記録（BLK-03 の永続化とセットで）
struct StudyLog: Codable { let cardId: UUID; let rating: Rating; let studiedAt: Date }

// ストリーク = 学習日が連続している日数（Calendar でカレンダー日単位に丸める）
// 本日の枚数 = 今日のログ件数
```

実装が間に合わない場合は、**表示自体を一時的に隠す**ほうが誠実です。

---

<a id="arc-05"></a>

## ARC-05: 設定画面の全項目がどこにも配線されていない

**深刻度**: 🟠 High
**該当**: `src/Views/SettingsView.swift:9-12`

`@AppStorage` で4つの設定を持っていますが、**`SettingsView.swift` の外で読まれているものは1つもありません**（全文検索で確認）。

| 設定キー | UI上の説明 | 実際の効果 |
|---|---|---|
| `dailyReviewLimit` | 1日の復習上限: N枚 | **なし**。学習枚数は `CourseDetailView` の 10/20/全件 で別途決まる |
| `enableAutoAudio` | カードめくり時の音声自動再生 | **なし**。`FlashcardView.swift:259-264` は設定を無視して常に自動再生する |
| `enableHaptics` | 触覚フィードバック (Haptics) | **なし**。Hapticsのコード自体が全く存在しない |
| `openAIApiKey` | AIカード自動生成 | **なし**。AI生成機能が未実装（→ [SEC-01](05-security-and-privacy.md#sec-01)） |

特に `enableAutoAudio` は、`.scratch/expert-improvements/spec.md` が明示的に「**設定でオンの場合**、裏面展開時に自動で音声朗読を実行」と書いており、仕様違反です。イヤホンなしの公共の場で意図せず音声が鳴るのは実害があります。

`enableHaptics` については、ADR-0001 が **SwiftUIネイティブを採用した理由の筆頭に「Haptics（触覚効果）のクオリティが最も高い」を挙げている** にもかかわらず、Hapticsが1箇所も実装されていない点が特に惜しいです。

### 推奨対応

設定を横断的に読める型を1つ用意し、各ビューから参照します。

```swift
// FlashcardView
@AppStorage("enableAutoAudio") private var enableAutoAudio: Bool = true

.onChange(of: isRevealed) { _, newValue in
    if newValue, enableAutoAudio { playBackSpeech() }
}

// CardStudyView — 判定時の触覚フィードバック (iOS 17+)
.sensoryFeedback(.impact(weight: .medium), trigger: currentIndex)
```

---

<a id="arc-06"></a>

## ARC-06: `@State` によるモデルのコピーが、親の変更を受け取れない

**深刻度**: 🟡 Medium
**該当**: `src/Views/CourseDetailView.swift:6, 21-24`

```swift
@State public var course: Course        // public な @State は設計上の匂い

public init(course: Course, onSaveCourse: @escaping (Course) -> Void) {
    self._course = State(initialValue: course)   // 値のスナップショットを保持
}
```

`@State` の初期値はビューのidentityが変わらない限り再評価されません。そのため:

- `DeckListView` 側でコースがアーカイブ・削除されても、開いているシートは古いコピーを持ち続ける
- シートを閉じずに `onSaveCourse` が呼ばれると、削除済みコースの復活や、アーカイブ状態の巻き戻りが起こりうる（`DeckStore.updateCourse` は `firstIndex(where:)` が見つからなければ何もしないので削除は救われますが、アーカイブ状態は上書きされます）
- `@State` を `public` にしているため、外部から `CourseDetailView(course:)` のセマンティクスが「初期値」なのか「バインディング」なのか読み取れない

### 推奨対応

`@Binding` またはIDベースの参照（`courseId` を受け取り、ストアから都度引く）に変更してください。SwiftDataを導入すれば `@Bindable var course: CourseEntity` が最も自然になります。

---

<a id="arc-07"></a>

## ARC-07: シートの3階層ネストは iPhone では扱いにくい

**深刻度**: 🟡 Medium
**該当**: `DeckListView.swift:113` → `CourseDetailView.swift:94` → `CardStudyView.swift:30`

現在の画面遷移はすべて `.sheet` です。

```
DeckListView (NavigationStack)
  └─ .sheet → CourseDetailView (NavigationStack)
       └─ .sheet → CardStudyView (NavigationStack)
            └─ .sheet → ImageDetailView (NavigationStack)   ※FlashcardView経由
```

iPhoneでは各シートが少しずつ縮んで重なり、4階層目にはコンテンツ領域がかなり削られます。加えて:

- 各階層が独立した `NavigationStack` を持つため、ナビゲーションバーが縦に積み上がる
- 端からのスワイプバックが効かない（シートは下スワイプのみ）
- Deep Link / 状態復元 (`NavigationPath`) が実装できない

コース → 詳細 のような**階層的ドリルダウンは `NavigationLink` / `navigationDestination`** が iOS の標準的な作法です。シートは「一時的なタスク（作成・編集）」に限定するのが定石で、`CreateCourseView` / `AddCardView` / `EditCardView` は現状のままシートで適切です。

### 推奨対応

```swift
// DeckListView
NavigationStack(path: $path) {
    mainList
        .navigationDestination(for: Course.ID.self) { courseId in
            CourseDetailView(courseId: courseId)
        }
}
```

`CardStudyView` は没入型セッションなので `.fullScreenCover` が適切です（現在のシート提示は BLK-05 の暴発リスクも抱えています）。

---

<a id="arc-08"></a>

## ARC-08: `@unchecked Sendable` が Swift 6 の並行性チェックを無効化している

**深刻度**: 🟡 Medium
**該当**: `src/Services/DeckStore.swift:6`, `src/Services/AudioService.swift:7`

```swift
@Observable
public final class DeckStore: @unchecked Sendable { ... }

@MainActor
public final class AudioService: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable { ... }
```

`Package.swift` は `swift-tools-version: 6.0` なので Swift 6 言語モードの厳格な並行性チェックが効く環境ですが、`@unchecked Sendable` は「コンパイラのチェックを開発者責任で黙らせる」宣言です。

- `DeckStore` は可変配列を保持し、ビューから同期的に変更されます。実際には常にMainActor上で動くはずなので、**正しい表明は `@MainActor`** です。`@unchecked Sendable` は「どのスレッドから触ってもよい」という誤った契約をAPI利用者に伝えます。
- `AudioService` は既に `@MainActor` が付いており、その上での `@unchecked Sendable` は冗長かつ有害です（`@MainActor` クラスは自動的に `Sendable` になります）。

このまま機能追加（バックグラウンド同期、ファイルI/O、AI生成のasync呼び出し）を進めると、コンパイラが検出できたはずのデータ競合が実行時クラッシュとして現れます。

### 推奨対応

```swift
@MainActor
@Observable
public final class DeckStore { ... }        // @unchecked Sendable を削除

@MainActor
public final class AudioService: NSObject, AVSpeechSynthesizerDelegate { ... }
```

---

<a id="arc-09"></a>

## ARC-09: 計算プロパティ内の全件フィルタが毎レンダリング走る

**深刻度**: 🔵 Low（カード数が増えると Medium）
**該当**: `src/Views/CourseDetailView.swift:27-41`

```swift
private var allCards: [AnkiCard] { course.decks.flatMap { $0.cards } }
private var totalMatchingCards: [AnkiCard] { StudyFilterConfig(target: filterTarget, batchSize: 0).filterCards(allCards) }
private var targetCards: [AnkiCard] { StudyFilterConfig(target: filterTarget, batchSize: batchSize).filterCards(allCards) }
```

`body` 内で `allCards.count`（1回）、`totalMatchingCards.count`（3回）、`targetCards.count`（2回）が参照されており、1レンダリングあたり **flatMap が6回、全件フィルタが5回** 実行されます。`AnkiCard` は20以上のプロパティを持つ大きめの構造体なので、配列のコピーコストも無視できません。

数十枚のサンプルデータでは問題になりませんが、実運用で数千枚のコースを扱うようになると、Pickerを操作するたびに体感できるカクつきが出ます。

### 推奨対応

- 集計は件数のみ必要なので、配列を作らず `filterCards` に対応する `matchCount(_:)` を用意する、あるいは `lazy.filter{}.count` を使う
- `filterTarget` / `batchSize` の変更時だけ再計算するよう `@State` にキャッシュする
- SwiftData 移行後は `@Query` の `#Predicate` でDB側に絞り込みを寄せる
