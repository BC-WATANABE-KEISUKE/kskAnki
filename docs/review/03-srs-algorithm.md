# 03. SRS（間隔反復）アルゴリズム

暗記アプリの中核価値そのものです。現状、**計算はしているが誰も結果を使っていない**という構造的な問題を抱えています。

対象: `src/Services/SpacedRepetition.swift`, `src/Models/AnkiCard.swift`, `src/Models/StudyFilter.swift`

---

<a id="srs-01"></a>

## SRS-01: `dueDate` が出題カードの選択に一切使われていない — SRSが機能していない

**深刻度**: 🔴 中核機能の不成立
**該当**: `src/Models/StudyFilter.swift:4-24`, `src/Models/AnkiDeck.swift:26-29`

`SpacedRepetitionScheduler` は毎回 `dueDate` を計算して `AnkiCard` に書き込みます（`SpacedRepetition.swift:46-48`）。しかし **`dueDate` を読んで出題対象を絞る経路が、アプリのどこにも存在しません。**

- `StudyFilterTarget` の13ケース（`StudyFilter.swift:4-24`）を全て確認しましたが、**期日ベースの条件が1つもありません**。「今日学習したもの」「昨日学習したもの」など**過去**の条件ばかりで、「今日復習すべきもの」という**未来**の条件がありません
- `AnkiDeck.dueCards`（`AnkiDeck.swift:26`）は正しく実装されていますが、**全文検索の結果、呼び出し箇所ゼロ**の完全なデッドコードです
- `CardStudyView` は `deck.cards` をそのまま `dueCards` という名前の `@State` に入れています（`CardStudyView.swift:25`）。名前に反して期日フィルタは一切かかっていません

結果として、ユーザーの学習体験は「フィルタ条件で選んだカードを、毎日何度でも同じように出す」というものになり、**間隔反復ではなく単なるカードめくり**です。`easeFactor` も `intervalDays` も、計算されてメモリ上に置かれるだけで誰も参照しません（BLK-03により保存すらされません）。

`REQUIREMENTS.md` 自体にも期日ベースの復習に関する要件が記述されておらず、要件定義の段階で SRS の本質が抜け落ちている可能性があります。アプリ名・アルゴリズム表記（設定画面に「SuperMemo SM-2」と明記）から期待される動作との乖離が大きい点は、要件レベルで議論すべきだと思います。

### 推奨対応

1. `StudyFilterTarget` に期日ベースの選択肢を追加し、**デフォルト条件にする**

```swift
case dueToday = "今日が復習日のもの（推奨）"
case overdue  = "復習日を過ぎているもの"

// filterCards 内
case .dueToday:
    filtered = cards.filter { Calendar.current.startOfDay(for: $0.dueDate) <= Calendar.current.startOfDay(for: Date()) }
```

2. トップ画面のコースカードに「今日の復習: N枚」バッジを出す（現状の「N枚」は総カード数で、行動を促しません）
3. `AnkiDeck.dueCards` をこの新フィルタから利用するか、重複実装なので削除する

---

<a id="srs-02"></a>

## SRS-02: `easeFactor` に上限がなく、復習間隔が指数的に発散する

**深刻度**: 🟠 High
**該当**: `src/Services/SpacedRepetition.swift:35`

```swift
case .correct:
    updatedCard.easeFactor += 0.05      // ← 上限なし
```

正解のたびに無条件で `easeFactor` が増え続けます。不正解時は `max(1.3, ...)` で下限のみ守られていますが、上限がありません。

初期値2.5から正解を重ねると:

| 正解回数 | easeFactor | reps=3以降の間隔の伸び方 |
|---|---|---|
| 10回 | 3.0 | 1日 → 4日 → 12日 → 36日 → 108日 |
| 30回 | 4.0 | 1日 → 4日 → 16日 → 64日 → 256日 |
| 50回 | 5.0 | 1日 → 4日 → 20日 → 100日 → 500日 |

`intervalDays` は `Int` なので、長期利用では数年〜オーバーフロー領域に達します。オリジナルのSM-2は品質評価 `q` に基づく式 `EF' = EF + (0.1 - (5-q)(0.08 + (5-q)0.02))` を使い、q=5（完璧）でも増分は +0.1 が上限で、実装上は 1.3〜2.5 程度に収束するよう設計されています。

### 推奨対応

```swift
updatedCard.easeFactor = min(2.5, updatedCard.easeFactor + 0.05)
```

併せて `intervalDays` にも実用的な上限（例: 365日）を設けてください。オーバーフローと「二度と出題されないカード」の両方を防げます。

---

<a id="srs-03"></a>

## SRS-03: 「△ 惜しい」で復習間隔が**伸びる**（学習効果と逆行）

**深刻度**: 🟠 High
**該当**: `src/Services/SpacedRepetition.swift:22-30`

```swift
case .doubtful: // △ 惜しい / 三角
    updatedCard.doubtfulCount += 1
    updatedCard.consecutiveCorrectCount = 0
    updatedCard.easeFactor = max(1.3, updatedCard.easeFactor - 0.1)
    if updatedCard.reps == 0 {
        updatedCard.intervalDays = 1
    } else {
        updatedCard.intervalDays = max(1, Int(round(Double(updatedCard.intervalDays) * 1.2)))  // ← 1.2倍に伸びる
    }
```

`REQUIREMENTS.md 3.3-②` は「**△ 惜しい**: 連続正解カウントリセット、**短期間隔で復習**」と定めています。しかし実装は間隔を **1.2倍に延長**しています。

「思い出せたが自信がなかった」カードは、正解カードより**短い**間隔で再提示するのが間隔反復の基本です（Ankiの "Hard" は現在間隔 × 1.2 ではなく、SM-2系では現在間隔 × 1.2 を使う実装もありますが、その場合の "Hard" は正解扱いで `reps` も進みます）。ここでは `consecutiveCorrectCount` をリセットして「不正解寄り」として扱いながら、間隔だけは伸ばすという矛盾した挙動になっています。

さらに `reps` をインクリメントもリセットもしないため、次の副作用があります。

**トレース例**:
1. 初回 ◯ → `reps=1`, `interval=1日`
2. △ → `reps=1`のまま, `interval = round(1 × 1.2) = 1日`（変化なし）
3. ◯ → `reps=2` → **`intervalDays = 4`（ハードコード代入）**

3ステップ目で `reps == 2` の分岐に入り、それまでの `intervalDays` を無視して固定値4を代入します。つまり **△の評価は最終的に何の影響も残しません**。

### 推奨対応

要件通り「短期間隔」にし、`reps` の扱いも明示してください。

```swift
case .doubtful:
    updatedCard.doubtfulCount += 1
    updatedCard.consecutiveCorrectCount = 0
    updatedCard.easeFactor = max(1.3, updatedCard.easeFactor - 0.15)
    // 間隔は短縮する（最低1日）
    updatedCard.intervalDays = max(1, Int(round(Double(max(1, updatedCard.intervalDays)) * 0.5)))
    // reps は据え置き（＝ラダーを進めない）ことを意図するならコメントで明記する
```

---

<a id="srs-04"></a>

## SRS-04: ✕ / △ をつけたカードが「未学習」に分類される

**深刻度**: 🟠 High
**該当**: `src/Services/SpacedRepetition.swift:16`, `src/Models/AnkiCard.swift:172-174`, `src/Models/StudyFilter.swift:79`

```swift
// AnkiCard.swift:172
public var isUnlearned: Bool { reps == 0 }

// SpacedRepetition.swift:16 — ✕ で reps を 0 に戻す
case .incorrect:
    updatedCard.reps = 0
```

`reps` を「連続正解の段数」として使いながら、`isUnlearned` は「一度も学習していない」の判定に使っています。**2つの異なる意味を1つのフィールドに載せている**ため、次の誤分類が起きます。

- ✕ を付けたカード → `reps = 0` → **「未学習のものだけ」フィルタに現れる**
- △ を付けたカード（初回） → `reps` は 0 のまま → **同様に「未学習」扱い**

要件3.2-3 は「未学習のものだけ: まだ一度も復習していないカード」と定義しているので、明確な仕様違反です。ユーザーから見ると「間違えたはずのカードが未学習リストに混ざる」「未学習リストがいつまでも減らない」という挙動になります。

### 推奨対応

「一度でも学習したか」は `lastStudiedAt` で判定してください。既にフィールドが存在します。

```swift
public var isUnlearned: Bool { lastStudiedAt == nil }
```

併せて、`reps` を「SM-2のラダー段数」と明示するリネーム（`successStreakStep` 等）を検討してください。命名が意味を語れば、この種の混線は再発しません。

---

<a id="srs-05"></a>

## SRS-05: 「4回連続◯で完全習得」が同一セッション内の数十秒で達成できる

**深刻度**: 🟠 High
**該当**: `src/Models/AnkiCard.swift:177-191`, `src/Models/StudyFilter.swift:77`

```swift
public var isMasteredFourTimes: Bool { consecutiveCorrectCount >= 4 }
public var isFullyMasteredActive: Bool { isMasteredFourTimes && !isMaintenanceNeeded }
```

SRS-01（期日による出題制御がない）と組み合わさると、**同じセッション内で同じカードに4回◯を付けるだけで「完全習得」になります**。学習枚数を「10枚」に設定して同じ10枚を4周すれば、数分で全カードが「4連勝除外」対象から消えます。

間隔反復における「習得」は「**時間を空けて**思い出せた回数」でしか定義できません。連続正解の間に最低限の日数の隔たりを要求しないと、この指標は学習効果を全く反映しません。要件3.2-2 の「4回連続で正解して完全習得したカードを自動除外」も、意図としては「日を跨いだ4回」のはずです。

### 推奨対応

「日を跨いだ正解」のみをカウントしてください。

```swift
// SpacedRepetitionScheduler.processReview 内
case .correct:
    let isNewDay = card.lastStudiedAt.map { !Calendar.current.isDate($0, inSameDayAs: currentDate) } ?? true
    if isNewDay {
        updatedCard.consecutiveCorrectCount += 1
    }
```

さらに、`isMasteredFourTimes` に「最終間隔が21日以上」といった間隔条件を併用すると、より妥当な習得判定になります（Ankiの "mature card" は21日が閾値です）。

---

<a id="srs-06"></a>

## SRS-06: 日付計算に `TimeInterval` の固定秒数を使っている（DST・タイムゾーンで1日ずれる）

**深刻度**: 🟡 Medium
**該当**: `src/Models/AnkiCard.swift:184, 208`

```swift
let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)   // :184
let oneWeekAgo    = Date().addingTimeInterval(-7 * 24 * 60 * 60)    // :208
```

同じファイル内の `isStudiedToday` / `isStudiedYesterday` は `Calendar.current.isDateInToday(_:)` を正しく使っているのに、期間判定だけ固定秒数になっており一貫性がありません。

- サマータイムのある地域では1時間ずれ、境界日で判定が1日ずれます
- 「1週間以内」がカレンダー日ではなく「168時間以内」になるため、7日前の朝に学習したカードが夕方には対象外になります。ユーザーの直感（＝カレンダー日）と合いません

### 推奨対応

```swift
public var isStudiedWithinOneWeek: Bool {
    guard let last = lastStudiedAt,
          let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return false }
    return Calendar.current.startOfDay(for: last) >= Calendar.current.startOfDay(for: oneWeekAgo)
}
```

---

<a id="srs-07"></a>

## SRS-07: 「1日の区切り」のポリシーが未定義（深夜学習で日付がずれる）

**深刻度**: 🟡 Medium
**該当**: `src/Models/AnkiCard.swift:194-203`

`isStudiedToday` は `Calendar.current.isDateInToday(_:)`、すなわち **午前0時区切り**です。

暗記アプリは「寝る前の学習」が中心的なユースケースで、深夜0時をまたいで学習するユーザーが必ず出ます。0時区切りだと:

- 23:50〜00:10 の1回の学習セッションが2日にまたがって記録される
- ストリーク（ARC-04で実装予定）が、日をまたいだだけで「2日連続」にカウントされる／逆に途切れる

Anki は既定で **午前4時** を1日の境界としており、デファクトスタンダードになっています。

### 推奨対応

日付境界を1箇所に集約し、設定可能にしてください。

```swift
enum StudyDay {
    static var rolloverHour: Int = 4
    static func day(for date: Date, calendar: Calendar = .current) -> Date {
        let shifted = calendar.date(byAdding: .hour, value: -rolloverHour, to: date)!
        return calendar.startOfDay(for: shifted)
    }
}
```

ストリーク・「今日学習したもの」・`dueToday` フィルタのすべてがこの1つの定義を参照するようにすれば、整合性が保てます。

---

<a id="srs-08"></a>

## SRS-08: 冗長な判定ロジック

**深刻度**: 🔵 Low
**該当**: `src/Models/AnkiCard.swift:226-232`

```swift
public var hasEverBeenTriangle: Bool { doubtfulCount > 0 || isWrongTriangleLastTime }
public var hasEverBeenCross: Bool    { wrongCount > 0    || isWrongCrossLastTime }
```

`doubtfulCount` は `.doubtful` を付けた瞬間に必ずインクリメントされる（`SpacedRepetition.swift:23`）ため、`lastRating == .doubtful` が真なら `doubtfulCount > 0` も必ず真です。`||` の右辺は到達不能で、動作上の害はありませんが「カウンタが信用できないのでは」という誤読を招きます。

### 推奨対応

```swift
public var hasEverBeenTriangle: Bool { doubtfulCount > 0 }
public var hasEverBeenCross: Bool    { wrongCount > 0 }
```

なお、この不変条件（カウンタと `lastRating` の整合）は**テストで固定すべき性質**です → [QA-01](06-code-quality-and-testing.md#qa-01)。
