# 09. クリーンコード / リファクタリング / 性能レビュー

- **レビュー日**: 2026-07-26（3回目）
- **観点**: ① クリーンコード ② 現時点で必要なリファクタリング ③ 性能
- **対象**: `src/` 全22ファイル（4,301行）
- **検証方法**: 全ソース精読 + 重複箇所の全文検索による定量化 + **`kskAnkiCore` を実際にリンクしたベンチマークの実行**

> 本ドキュメントは**設計品質**に焦点を当てています。機能の欠落・バグについては [08. 追補レビュー](08-followup-review.md) を参照してください。

---

## 総評

**性能に、実測で確認できる深刻な問題が3件あります。** 現実的なデータ規模（カード5,000枚 / 学習ログ14,600件 = 2年分）でベンチマークを実行したところ、**学習統計画面の1レンダリングに約1.04秒**、**トップ画面の1レンダリングに約54ms**（60fpsのフレーム予算16.7msの3.2倍）、**学習セッション終了時に約2秒のフリーズ**という結果になりました。いずれも「使い込むほど遅くなる」構造で、暗記アプリの性質上、時間とともに必ず顕在化します。

原因は共通していて、**`@Observable` の計算プロパティに重い処理を置き、それを `body` から複数回参照している**ことです。SwiftUIの `body` はレンダリングのたびに評価されるため、計算プロパティは「ほぼ毎フレーム実行される関数」として設計する必要があります。

一方、**過剰に心配する必要のない箇所も実測で確認できました**。`Course` 構造体の値型コピーは 0.005ms、`allDecks` の flatMap は 0.003ms で、Swiftのコピーオンライトが正しく効いています。ここを最適化する必要はありません。

クリーンコードの観点では、**`AddCardView` と `EditCardView` の間に約180行の実質的な重複**があり、これが [NEW-04](08-followup-review.md#new-04) のような「片方だけ直る」バグの温床になっています。また `AnkiCard` が32個の格納プロパティと67行の手書きイニシャライザを抱え、4つの異なる責務を1つの型に載せている点が、今後の変更コストを押し上げます。

---

## 指摘サマリー（全25件）

| 区分 | 件数 | 内訳 |
|---|---|---|
| 🔴 性能・重大 | 3 | PERF-01〜03（実測値あり） |
| 🟠 性能・高 | 3 | PERF-04〜06 |
| 🟠 リファクタリング・高 | 4 | RFC-01〜04 |
| 🟡 中 | 12 | CLN-01〜08, RFC-05〜08 |
| 🔵 低 | 3 | CLN-09〜10, RFC-09 |

---

## 📊 ベンチマーク実測値

`kskAnkiCore` を実際にリンクし、release ビルドで計測しました（Apple Silicon / macOS）。

**データ規模**: 20コース × 5デッキ × 50枚 = **カード5,000枚** / **学習ログ14,600件**（1日20枚 × 2年）

| 計測対象 | 1回あたり | 評価 |
|---|---:|---|
| `DeckStore.streakDaysCount` | **18.02 ms** | 🔴 `body` から毎回参照 |
| `DeckStore.todayStudiedCardsCount` | **18.07 ms** | 🔴 `body` から**2回**参照 |
| `StudyStatsView.last7DaysStats` 相当 | **125.73 ms** | 🔴 `body` から**8回**参照 |
| `DeckStore.saveToDisk()` | **84.12 ms** | 🔴 カード1枚更新ごとに実行 |
| `StudyFilterConfig.filterCards(.dueToday)` | 6.41 ms | 🟠 条件変更ごとに2回 |
| `ratingCounts` 相当（全ログ走査） | 0.145 ms | 🟡 `body` から7回参照 |
| `courses.flatMap.flatMap`（allCards生成） | 0.53 ms | 🟡 許容範囲 |
| `DeckStore.allDecks` | 0.003 ms | ✅ 問題なし |
| `Course` 構造体コピー + 1枚書換 | 0.005 ms | ✅ 問題なし（COWが有効） |

---

# 🔴 性能

<a id="perf-01"></a>

## PERF-01: 学習統計画面の1レンダリングに約1.04秒かかる

**深刻度**: 🔴 Critical
**該当**: `src/Views/StudyStatsView.swift:16-32, 47-49, 143-167`

`last7DaysStats` は「7日ぶんのループ × 全学習ログの走査」に加え、**呼び出しのたびに `DateFormatter` を生成**しています。

```swift
private var last7DaysStats: [(date: Date, label: String, count: Int)] {
    let formatter = DateFormatter()                       // ← 毎回生成（高コスト）
    formatter.dateFormat = "M/d(eee)"
    formatter.locale = Locale(identifier: "ja_JP")
    for i in (0..<7).reversed() {
        let count = store.studyLogs.filter {              // ← 全ログを7回走査
            calendar.isDate($0.studiedAt, inSameDayAs: date)
        }.count
    }
}
```

実測で **1回あたり 125.73 ms**。問題はこれが `body` の1レンダリングで **8回**評価されることです。

```swift
ForEach(last7DaysStats, id: \.label) { stat in           // ← 1回目
    ...
    GeometryReader { geo in
        RoundedRectangle(cornerRadius: 6)
            .frame(height: max(6, geo.size.height * CGFloat(stat.count) / CGFloat(maxDailyCount)))
                                                          //   ↑ 棒7本ぶん = 7回
    }
}

private var maxDailyCount: Int {
    max(1, last7DaysStats.map(\.count).max() ?? 1)        // ← 内部で last7DaysStats を再計算
}
```

`maxDailyCount` は棒グラフの**各バーの `GeometryReader` クロージャの中**で参照されており、7本ぶん評価されます。そのたびに `last7DaysStats` がまるごと再計算されます。

**1レンダリングの合計**:

| 項目 | 回数 | コスト |
|---|---:|---:|
| `last7DaysStats`（ForEach） | 1 | 125.7 ms |
| `maxDailyCount` → `last7DaysStats`（バー7本） | 7 | 880.1 ms |
| `store.streakDaysCount` | 1 | 18.0 ms |
| `store.todayStudiedCardsCount` | 1 | 18.1 ms |
| **合計** | | **約 1,042 ms** |

`GeometryReader` はレイアウトパスごとにクロージャを再評価するため、実際にはこれ以上になる可能性があります。**統計画面を開くだけで1秒以上メインスレッドが固まります。**

### 推奨対応

集計結果を1度だけ計算し、値として保持してください。ビューが表示された時に1回計算すれば十分です。

```swift
struct DailyStat: Identifiable { let id = UUID(); let label: String; let count: Int }

@State private var stats: [DailyStat] = []
@State private var maxCount: Int = 1
@State private var ratings: (correct: Int, doubtful: Int, incorrect: Int) = (0, 0, 0)

.task { recalculate() }     // 表示時に1回だけ

private func recalculate() {
    let calendar = Calendar.current
    // ログを1回だけ走査して日付ごとに集計する（O(7n) → O(n)）
    var byDay: [Date: Int] = [:]
    var c = 0, d = 0, i = 0
    for log in store.studyLogs {
        byDay[calendar.startOfDay(for: log.studiedAt), default: 0] += 1
        switch log.rating { case .correct: c += 1; case .doubtful: d += 1; case .incorrect: i += 1 }
    }
    ...
}
```

`DateFormatter` は `static let` にしてください（生成コストが高く、使い回しが前提のクラスです）。

```swift
private static let dayLabelFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "M/d(eee)"
    f.locale = Locale(identifier: "ja_JP")
    return f
}()
```

---

<a id="perf-02"></a>

## PERF-02: トップ画面の1レンダリングが54ms — フレーム予算の3.2倍

**深刻度**: 🔴 Critical
**該当**: `src/Services/DeckStore.swift:41-73`, `src/Views/DeckListView.swift:165, 183, 188`

`DeckStore` のストリーク・本日枚数は計算プロパティで、実測で**それぞれ約18ms**かかります。

```swift
public var todayStudiedCardsCount: Int {
    studyLogs.filter { calendar.isDateInToday($0.studiedAt) }.count      // 全ログ走査
}

public var streakDaysCount: Int {
    let studyDates = Set(studyLogs.map { calendar.startOfDay(for: $0.studiedAt) })  // 全ログぶん startOfDay
    ...
}
```

`DeckListView.body` はこれらを合計3回参照します。

```swift
Text("\(store.streakDaysCount)日連続学習中！")                                    // 18.0 ms
Text("\(store.todayStudiedCardsCount) / \(store.dailyGoalCardsCount) 枚")        // 18.1 ms
ProgressView(value: Double(store.todayStudiedCardsCount), ...)                   // 18.1 ms
                                                                    // 合計 54.2 ms
```

60fps のフレーム予算は 16.7ms なので、**トップ画面はレンダリングのたびに3フレーム以上落とします**。`List` のスクロール、フォルダチップのタップ、ページ送り、`@Observable` のあらゆる変更通知でこれが再実行されます。体感は「トップ画面全体がカクつく・タップの反応が鈍い」というものになります。

しかもこれは**学習ログが増えるほど線形に悪化**します。上記は2年ぶんの想定ですが、5年使えば約135msになります。

### 推奨対応

1. **`body` からの多重参照をやめる**（即効性あり、コストは1/3に）

```swift
let todayCount = store.todayStudiedCardsCount    // 1回だけ読む
Text("\(todayCount) / \(store.dailyGoalCardsCount) 枚")
ProgressView(value: Double(todayCount), total: Double(store.dailyGoalCardsCount))
```

2. **集計値をキャッシュする**（根本対応）。ログ追加時にだけ再計算し、`DeckStore` には格納プロパティとして持たせます。

```swift
public private(set) var streakDaysCount: Int = 0
public private(set) var todayStudiedCardsCount: Int = 0

public func recordStudy(cardId: UUID, rating: Rating, at date: Date = Date()) {
    studyLogs.append(...)
    refreshStatistics()      // ここでだけ再計算
}
```

3. **日単位の集計を保持する**（[PERF-04](#perf-04) / [NEW-17](08-followup-review.md#new-17) と併せて）。生ログを全走査する設計自体をやめれば、O(1)に近づきます。

---

<a id="perf-03"></a>

## PERF-03: 学習セッション終了時に約2秒フリーズする

**深刻度**: 🔴 Critical
**該当**: `src/Views/CourseDetailView.swift:87-93, 264-288`, `src/Views/DeckListView.swift:139, 146`, `src/Services/DeckStore.swift:96-112`

`saveToDisk()` は**全ストア（全コース・全カード・全学習ログ）を毎回JSONエンコードして書き込みます**。実測で **1回あたり 84.12 ms**。

セッション終了時、判定済みカードを1枚ずつループで書き戻すため、これが枚数ぶん実行されます。

```swift
for card in sessionCards {
    updateSingleCardInCourse(card)     // → onSaveCourse → store.updateCourse → saveToDisk()
}
```

**20枚のセッションを終えた場合の実測ベースの見積り**:

| 処理 | 回数 | 小計 |
|---|---:|---:|
| `saveToDisk()`（全ストアJSONエンコード + 書込） | 20 | 1,682 ms |
| `recalculateFilteredCards()`（filterCards × 2） | 20 | 256 ms |
| `allCards` の flatMap × 2 | 20 | 21 ms |
| **合計** | | **約 1,959 ms** |

すべて `@MainActor` 上の同期処理なので、**「コース画面に戻る」を押してから約2秒、UIが完全に固まります**。「マイ単語帳」経路（`store.updateCard` を20回）も同じ構造です。

さらに `saveToDisk` は `.atomic` 指定なので、毎回テンポラリファイル生成→`rename` のシステムコールも走ります。

### 推奨対応

**一括更新して、保存は1回**にしてください。これだけで約2秒が約0.1秒になります。

```swift
// DeckStore 側
public func applySessionResults(_ cards: [AnkiCard], logs: [StudyLog]) {
    var index: [UUID: AnkiCard] = [:]
    cards.forEach { index[$0.id] = $0 }
    for cIdx in courses.indices {
        for dIdx in courses[cIdx].decks.indices {
            for kIdx in courses[cIdx].decks[dIdx].cards.indices {
                if let updated = index[courses[cIdx].decks[dIdx].cards[kIdx].id] {
                    courses[cIdx].decks[dIdx].cards[kIdx] = updated
                }
            }
        }
    }
    studyLogs.append(contentsOf: logs)
    saveToDisk()                      // ← 最後に1回だけ
}
```

加えて:

- **保存をデバウンスする**（変更後0.5秒待ってまとめて書く）
- **エンコードと書き込みをメインスレッドから外す**。スナップショットは `Sendable` なので `Task.detached` へ渡せます
- 中期的には全書き換えをやめ、差分更新できる SwiftData / SQLite へ移行する（ADR-0001 の当初方針）

---

<a id="perf-04"></a>

## PERF-04: `Calendar` API がホットパスに置かれている

**深刻度**: 🟠 High
**該当**: `src/Services/DeckStore.swift:43, 52`, `src/Views/StudyStatsView.swift:26`, `src/Models/AnkiCard.swift:184, 196, 202, 208`

PERF-01・PERF-02 の真因です。ベンチマークで **14,600件の走査に約18ms** かかりましたが、これは配列走査が遅いのではなく **`Calendar` の日付計算が1件あたり約1.2µs と高コスト**なためです（`ratingCounts` のような `Calendar` を使わない全ログ走査は 0.145ms、**約124倍高速**でした）。

`Calendar.isDateInToday` / `startOfDay(for:)` / `isDate(_:inSameDayAs:)` は、内部でタイムゾーン解決とカレンダー計算を毎回行います。ループ内で呼ぶべきAPIではありません。

### 推奨対応

- **ループの外で基準値を1回だけ計算し、以降は `Date` の単純比較にする**

```swift
// 悪い例: 1件ごとに Calendar を呼ぶ
studyLogs.filter { calendar.isDateInToday($0.studiedAt) }

// 良い例: 境界を1回だけ求め、あとは範囲比較
let start = calendar.startOfDay(for: Date())
let end = calendar.date(byAdding: .day, value: 1, to: start)!
studyLogs.filter { $0.studiedAt >= start && $0.studiedAt < end }
```

- `Calendar.current` はアクセスのたびにコピーが生じるため、`let calendar = Calendar.current` でローカルに束縛してから使う
- `AnkiCard` の日付判定プロパティ（`isStudiedToday` 等）も同様で、`filterCards` から5,000枚ぶん呼ばれます。基準日を引数で受け取る関数に変えると、呼び出し側で1回計算した境界を使い回せます（[NEW-16](08-followup-review.md#new-16) と同じ方向の修正です）

---

<a id="perf-05"></a>

## PERF-05: 画像がフルサイズでデコードされ、キャッシュもされない

**深刻度**: 🟠 High
**該当**: `src/Services/ImageStore.swift:15-40`, `src/Views/FlashcardView.swift:362-385`

2つの問題が重なっています。

**(a) 保存時にリサイズ・再圧縮していない**

```swift
public static func saveImage(data: Data) throws -> String {
    let fileName = "\(UUID().uuidString).jpg"
    try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
}
```

`PhotosPicker` から受け取った**オリジナルデータをそのまま保存**しています。最近のiPhoneの写真は1枚3〜5MB（12〜48MP）です。カード1枚に表裏5枚ずつ登録すれば数十MB、100枚のカードで数GBに達します。

なお、拡張子を `.jpg` と決め打ちしていますが、iOSの写真は既定で **HEIC** です。中身と拡張子が食い違っています（`UIImage` は内容から判別するため動作はしますが、書き出し・共有時に問題になります）。

**(b) 表示時にフルサイズをデコードし、毎レンダリング繰り返す**

```swift
// FlashcardView.swift:374 — body の評価中に実行される
if let uiImage = ImageStore.loadImage(path: urlString) {
    Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
}
.frame(width: 140, height: 100)      // ← 実際の表示サイズは 140×100 pt
```

`UIImage(contentsOfFile:)` はフルサイズのビットマップをメモリに展開します。12MPの写真1枚で約48MBです。それを **140×100pt** で表示しています。しかもこの呼び出しは `body` の中にあるため、**レンダリングのたびにディスクI/O + デコードが走ります**（キャッシュなし）。

学習中はカードを次々にめくるため、メモリ警告やジェッサム（強制終了）に至る現実的なリスクがあります。

### 推奨対応

**保存時にダウンサンプリングする**のが最も効果的です。

```swift
public static func saveImage(data: Data, maxPixelSize: CGFloat = 1600) throws -> String {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw ImageStoreError.invalidData }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceCreateThumbnailWithTransform: true
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
          let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8) else { throw ... }
    // 以降 jpeg を書き出す（拡張子 .jpg と中身が一致する）
}
```

表示側も、`body` から直接デコードするのをやめてください。

- サムネイル用の小さい画像を別途保存し、一覧ではそちらを使う
- デコード結果を `NSCache<NSString, UIImage>` でキャッシュする
- 読み込みは `.task` で非同期に行い、`@State` に保持する

---

<a id="perf-06"></a>

## PERF-06: 件数しか要らない場面で配列コピーを作っている

**深刻度**: 🟡 Medium
**該当**: `src/Views/CourseDetailView.swift:124-133`

ARC-09 への対応でキャッシュ化されたのは正しい改善です。ただし `cachedMatchingCards` は**件数表示にしか使われていません**。

```swift
Text("該当: \(cachedMatchingCards.count) 枚")           // :190
Text("全件 (\(cachedMatchingCards.count)枚)").tag(0)     // :209
Text("\(cachedTargetCards.count) / \(cachedMatchingCards.count) 枚")  // :223
```

`filterCards` は条件に合う `AnkiCard`（32プロパティの大きな構造体）を**すべて新しい配列にコピーして返します**。実測で5,000枚に対し 6.41 ms、これが `recalculateFilteredCards()` で2回走ります（約13ms）。フィルタ条件や枚数を変えるたびに発生します。

件数だけなら配列を作る必要はありません。

### 推奨対応

述語を切り出し、件数用のAPIを分けてください（[CLN-02](#cln-02) の対応と合わせると自然に実現します）。

```swift
extension StudyFilterTarget {
    func matches(_ card: AnkiCard, on date: Date) -> Bool { ... }
}

// 件数のみ: 配列を作らない
let matchCount = allCards.lazy.filter { filterTarget.matches($0, on: now) }.count
// セッション用: ここで初めて配列化
let session = allCards.lazy.filter { ... }.prefix(batchSize)
```

---

## ✅ 性能上の問題が無いと確認できた箇所

公平のため、**最適化が不要だと実測で確認できた箇所**も記録します。

| 箇所 | 実測 | 判断 |
|---|---:|---|
| `Course` 構造体のコピー（250枚保持） | 0.005 ms | ✅ Swiftのコピーオンライトが正しく効いています。`var updatedCourse = course` を避けるようなリファクタリングは不要です |
| `DeckStore.allDecks`（20コースの flatMap） | 0.003 ms | ✅ `body` から2回参照されていますが問題ありません |
| `DeckListView` のソート（20コース） | ─ | ✅ `Course` のコピーが 0.005ms である以上、20件のソートを6回繰り返しても 1ms 未満です。現状の規模では対処不要 |
| `ratingCounts`（14,600件の走査） | 0.145 ms | ✅ `body` から7回参照されますが合計1ms程度。`Calendar` を使わない走査は十分速いという良い対照例です |

**要点**: 「値型のコピー」や「flatMap」を疑うのではなく、**`Calendar` API と JSON エンコードと画像デコード**という3つの重い処理がどこに置かれているかを見てください。

---

# 🟠 リファクタリング

<a id="rfc-01"></a>

## RFC-01: `AddCardView` と `EditCardView` に約180行の重複がある

**深刻度**: 🟠 High
**該当**: `src/Views/AddCardView.swift:111-187, 228-251`, `src/Views/EditCardView.swift:99-175, 218-241`

画像セクションのUIが**「表面用」「裏面用」× 「追加画面」「編集画面」の4箇所にコピー**されています。1ブロック約45行で、合計約180行が実質同一です。

```
$ grep -rn "画像Web URL (カンマ区切り)" src
AddCardView.swift:113   AddCardView.swift:152
EditCardView.swift:101  EditCardView.swift:140      ← 4箇所

$ grep -rn "loadTransferable" src
AddCardView.swift:231   AddCardView.swift:243
EditCardView.swift:221  EditCardView.swift:233      ← 同じ12行が4箇所
```

これは既に実害を出しています。初回レビューの UX-03（PhotosPicker未実装）を直す際、**同じ修正を4箇所に入れる**必要がありました。今後も画像まわりの変更は毎回4箇所の同期が要ります（[PERF-05](#perf-05) のダウンサンプリング対応もそうです）。

### 推奨対応

セクションごと1つのコンポーネントに抽出してください。

```swift
struct CardImageSection: View {
    let title: String
    let accentColor: Color
    @Binding var imagePaths: [String]
    @Binding var urlInput: String
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        Section(title) {
            TextField("画像Web URL (カンマ区切り)", text: $urlInput)
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 5, matching: .images) { ... }
            ForEach(imagePaths, id: \.self) { path in imageRow(path) }
        }
        .onChange(of: pickerItems) { _, items in Task { await importImages(items) } }
    }
}

// 呼び出し側は4行で済む
CardImageSection(title: "📷 表面の画像", accentColor: .blue,
                 imagePaths: $frontImageURLs, urlInput: $frontImagesInput)
CardImageSection(title: "📷 裏面の画像", accentColor: .orange,
                 imagePaths: $backImageURLs, urlInput: $backImagesInput)
```

**約180行が約60行になり、修正箇所が4→1になります。**

---

<a id="rfc-02"></a>

## RFC-02: カード編集フォームの状態が14個の `@State` に分解されている

**深刻度**: 🟠 High
**該当**: `src/Views/AddCardView.swift:10-39`, `src/Views/EditCardView.swift:8-35`

`AddCardView` は14個、`EditCardView` は17個の `@State` でフォームの状態を持っています。その結果:

- **`EditCardView.init` が23行**、フィールドを1つずつ `State(initialValue:)` で初期化（`:40-64`）
- **保存処理が40行のクロージャ**として `toolbar` のボタンに直接埋め込まれている（`:253-291`）
- **`AddCardView.saveSingleCard` の後半14行がフォームリセットの手作業**（`:337-352`）

フィールドを1つ追加するたびに、**宣言・init・保存・リセットの4箇所**を触る必要があります。実際、初回レビューで指摘した「`AddCardView` には読み上げ言語のピッカーが無い」（`EditCardView` にはある）という不整合は、この構造が原因で生じています。

### 推奨対応

フォーム状態を1つの値型にまとめてください。

```swift
struct CardFormState {
    var frontType: CardFrontType = .question
    var frontText = ""
    var backText = ""
    // ... 以下フィールド

    init() {}
    init(from card: AnkiCard) { /* 1箇所でマッピング */ }
    func applying(to card: AnkiCard) -> AnkiCard { /* 1箇所でマッピング */ }
    func makeCard() -> AnkiCard { /* 1箇所で生成 */ }
    var isValid: Bool { !frontText.isEmpty && !backText.isEmpty }
}

// View 側
@State private var form = CardFormState()
```

これで `EditCardView.init` の23行、保存クロージャの40行、リセットの14行がすべて `CardFormState` の中に集約され、フィールド追加時の変更が1箇所になります。フォームのバリデーションも単体テストできるようになります。

---

<a id="rfc-03"></a>

## RFC-03: ドメインロジックが `View` の private メソッドに埋まっている

**深刻度**: 🟠 High
**該当**: `src/Views/FlashcardView.swift:316-339`（穴埋めパーサ）, `src/Views/AddCardView.swift:356-404`（CSVパーサ）

2つの純粋なテキスト処理ロジックが `View` の内部に閉じ込められています。

| ロジック | 場所 | 問題 |
|---|---|---|
| `parseCloze` | `FlashcardView.swift:316` | `showHint`（`@State`）を暗黙に参照しており、副作用を持つ純粋関数になっていない。**単体テスト不可** |
| `importCSV` | `AddCardView.swift:356` | パース・バリデーション・上限判定・UI状態更新が1つの関数に同居。**単体テスト不可** |

これは実害に直結しています。[NEW-04](08-followup-review.md#new-04)（複数空欄で誤った頭文字が出る）は、**パーサが独立した型であれば数行のテストで検出できたバグ**です。同様に QA-02（CSVの引用符非対応）も、テストがあれば修正が確認できます。

`parseCloze` は特に問題で、シグネチャは `(String) -> (String, String?)` と純粋関数に見えますが、実際は `self.showHint` を読んでいます。

### 推奨対応

`src/Models/`（または `src/Services/`）へ、状態を持たない型として切り出してください。

```swift
// src/Models/ClozeParser.swift
public struct ClozeParser: Sendable {
    public struct Blank: Sendable { public let range: Range<String.Index>; public let word: String }

    public func blanks(in text: String) -> [Blank]
    public func masked(_ text: String, revealedHints: Set<Int>) -> String
}

// src/Services/CSVCardParser.swift
public struct CSVCardParser: Sendable {
    public struct Result { public let cards: [AnkiCard]; public let skipped: [(line: Int, reason: String)] }
    public func parse(_ text: String) -> Result
}
```

どちらも入出力が明確なので、テストは10行程度で書けます。[NEW-01](08-followup-review.md#new-01)（テストが実行されていない）を解消したあと、最初にテストを書く対象として最適です。

---

<a id="rfc-04"></a>

## RFC-04: `CourseDetailView` の4つの更新メソッドが同じ処理を繰り返している

**深刻度**: 🟠 High
**該当**: `src/Views/CourseDetailView.swift:264-327`

`updateSingleCardInCourse` / `updateAllCards` / `deleteCardFromCourse` / `addCardsToCourse` の4つが、まったく同じ定型を繰り返しています。

```swift
var updatedCourse = course
/* --- ここだけが違う --- */
updatedCourse.updatedAt = Date()
self.course = updatedCourse
recalculateFilteredCards()
onSaveCourse(updatedCourse)
```

この重複が実害を生んでいます。ARC-02（デッキ破壊バグ）の修正時、**3つは全デッキ走査に直されましたが `updateAllCards` だけが取り残され**、カード重複バグとして残存しています（[NEW-10](08-followup-review.md#new-10)）。「同じことをする4つの場所」があると、必ず1つが漏れます。

また、`recalculateFilteredCards()` と `onSaveCourse()` が各メソッドに入っているため、ループから呼ぶと [PERF-03](#perf-03) の2秒フリーズになります。

### 推奨対応

共通部分を1つの関数に集約し、差分だけをクロージャで受け取ってください。

```swift
private func mutateCourse(_ mutation: (inout Course) -> Void) {
    var updated = course
    mutation(&updated)
    updated.updatedAt = Date()
    course = updated
    recalculateFilteredCards()
    onSaveCourse(updated)
}

// 呼び出し側
private func deleteCard(_ cardId: UUID) {
    mutateCourse { course in
        for i in course.decks.indices { course.decks[i].cards.removeAll { $0.id == cardId } }
    }
}
```

さらに、セッション結果のような一括更新には**保存を1回にまとめる専用の入口**を用意してください（[PERF-03](#perf-03)）。

---

<a id="rfc-05"></a>

## RFC-05: `DeckStore` の3割がサンプルデータのハードコード

**深刻度**: 🟡 Medium
**該当**: `src/Services/DeckStore.swift:198-286`

初回レビュー（ARC-03）からサンプルデータは6コース340行 → 2コース88行に削減されましたが、**依然としてファイル287行中の88行（31%）**を占めています。データ管理の本体ロジックを読む際に、無関係なサンプル文字列をスクロールする必要があります。

また、サンプル投入がイニシャライザに埋まっている点も変わっていません。

```swift
public init(folders: [CourseFolder] = [], courses: [Course] = []) {
    if !loadFromDisk() {
        self.folders = folders.isEmpty ? DeckStore.sampleFolders : folders   // ← 生成責務が混入
        ...
    }
}
```

「保存済みデータが無ければサンプルを入れる」は初回起動時のシード処理であり、ストアの構築責務とは別です。テストで「空のストア」を作れない原因にもなっています（[NEW-14](08-followup-review.md#new-14) の非密閉テストと同根）。

### 推奨対応

- サンプルデータを `src/Services/SampleData.swift` へ移動する
- シード処理を明示的なメソッドに分ける

```swift
public init(storageURL: URL? = nil) { ... }        // 空でも構築できる
public func seedIfEmpty() { ... }                  // 呼び出し側が意図して実行する
```

---

<a id="rfc-06"></a>

## RFC-06: `FlashcardView` が466行で5つの責務を持つ

**深刻度**: 🟡 Medium
**該当**: `src/Views/FlashcardView.swift`

初回レビュー時の565行から466行に減りましたが（ScrollView排除の効果）、依然として1つの `View` に以下が同居しています。

1. 表面の3パターン描画（`frontContentView`, `clozeFrontView`）
2. 穴埋めのパース（`parseCloze` → [RFC-03](#rfc-03)）
3. 裏面の8種類の詳細フィールド描画（`body` 内 `:85-207` の123行）
4. 画像グリッドとローカル/リモート分岐（`imageGridView`, `cardImageView`）
5. メモのインライン編集（`myNotesSection`）

`body` そのものが210行あり、裏面ブロックのネストが最大6段になっています。

### 推奨対応

```
CardFrontView      … 表面3パターン（ClozeParser を利用）
CardBackDetailView … 裏面の詳細フィールド群
CardImageGallery   … 画像グリッド（PERF-05 のキャッシュもここに閉じる）
UserNotesEditor    … メモ編集
```

分割すると [PERF-05](#perf-05)（画像キャッシュ）の実装先が明確になり、SwiftUIの再描画範囲も狭まるという副次効果があります。

---

<a id="rfc-07"></a>

## RFC-07: 「カンマ区切り文字列 ↔ 配列」の変換が7箇所に散在

**深刻度**: 🟡 Medium

```
$ grep -rn 'components(separatedBy: ",")' src | wc -l
7
```

タグ、表面画像URL、裏面画像URLの3種 × 追加/編集の2画面 + CSVで、同じ3行のイディオムが繰り返されています。

```swift
tagInput.components(separatedBy: ",")
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
```

### 推奨対応

```swift
extension String {
    /// カンマ区切り文字列を、trim・空要素除去したうえで配列化する
    var commaSeparatedList: [String] {
        components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
```

ついでに、初回レビュー QA-04（`Array(Set(...))` で画像の順序が崩れる、`AddCardView:312` / `EditCardView:276` に残存）も、順序保持版の `uniqued()` を同じ場所に置けば一度に解決できます。

---

<a id="rfc-08"></a>

## RFC-08: 背景色ヘルパーが5箇所に重複し、デザイントークンが存在しない

**深刻度**: 🟡 Medium
**該当**: `DeckListView.swift:512`, `FlashcardView.swift:438, 446`, `StudyStatsView.swift:228, 236`

同じ形の `#if canImport(UIKit)` 分岐が5箇所にコピーされています。

```swift
private var cardBgColor: Color {
    #if canImport(UIKit)
    return Color(uiColor: .secondarySystemGroupedBackground)
    #else
    return Color.gray.opacity(0.12)
    #endif
}
```

macOS側のフォールバック値が**箇所ごとにバラバラ**（`Color.gray.opacity(0.1)` / `0.12` / `Color.white`）で、既に一貫性が失われています。`StudyStatsView.swift:240` の `Color.white` はダークモードで問題になります（初回レビュー UX-08 と同種）。

`REQUIREMENTS.md 4.1` が要求する「curated HSL カラーパレット」に相当する定義は、今も存在しません。

### 推奨対応

1ファイルに集約してください。

```swift
// src/Views/Theme.swift
public extension Color {
    static var cardSurface: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color.gray.opacity(0.12)
        #endif
    }
    static var cardSurfaceElevated: Color { ... }
    static var screenBackground: Color { ... }
}
```

判定色（`.green` / `.orange` / `.red`）やタイプ別バッジ色も同様に `Color.ratingCorrect` のような意味のある名前にまとめると、要件のカラーパレット要求に対する答えにもなります。

---

# 🟡 クリーンコード

<a id="cln-01"></a>

## CLN-01: `AnkiCard` が32個の格納プロパティと67行の手書きイニシャライザを持つ

**深刻度**: 🟡 Medium
**該当**: `src/Models/AnkiCard.swift:52-157`

1つの構造体に**4つの異なる責務**が同居しています。

| 責務 | プロパティ | 変更の理由 |
|---|---|---|
| カードの内容 | `frontText`, `backText`, `explanation1〜3`, `japaneseTranslation`, `exampleSentence`, `exampleTranslation`, `synonyms`, `antonyms` | 表示項目の追加 |
| メディア | `frontImageURLs`, `backImageURLs`, `frontAudioURL`, `backAudioURL`, `speechLanguage` | 添付機能の変更 |
| 分類 | `mainCategory`, `subCategory`, `tags`, `isFavorite` | 整理機能の変更 |
| 学習状態 | `reps`, `intervalDays`, `easeFactor`, `dueDate`, `lastStudiedAt`, `lastRating`, `wrongCount`, `doubtfulCount`, `consecutiveCorrectCount` | **SRSアルゴリズムの変更** |

結果として:

- **手書きの `init` が67行**（`:91-157`）。フィールド追加のたびに3箇所（宣言・引数・代入）を触る
- **SRSアルゴリズムを変えるだけで、テキスト表示用の型が変更対象になる**
- 「解説4を追加したい」といった要望のたびに `explanation4` を足す設計になっており、スケールしない（`[Explanation]` 配列であるべき）

### 推奨対応

責務ごとに分割してください。

```swift
public struct ReviewState: Codable, Equatable, Sendable {
    public var reps: Int = 0
    public var intervalDays: Int = 0
    public var easeFactor: Double = 2.5
    public var dueDate: Date = Date()
    public var lastStudiedAt: Date?
    public var lastRating: Rating?
    public var wrongCount: Int = 0
    public var doubtfulCount: Int = 0
    public var consecutiveCorrectCount: Int = 0
}

public struct AnkiCard: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var content: CardContent
    public var media: CardMedia
    public var classification: CardClassification
    public var review: ReviewState
}
```

こうすると `SpacedRepetitionScheduler` のシグネチャが `(ReviewState, Rating, Date) -> ReviewState` になり、**SRSのテストがカードの表示内容から完全に独立します**。デフォルト値を持つ構造体はメンバワイズイニシャライザが自動生成されるため、67行の手書き `init` も不要になります。

> **注**: これは `Codable` の形式が変わるため、[BLK-03](01-blockers.md#blk-03) で導入した永続化データのマイグレーションが必要です。**保存データが増える前の今が、実施すべきタイミング**です。

---

<a id="cln-02"></a>

## CLN-02: フィルタ条件がenumとモデルの2箇所で二重管理されている

**深刻度**: 🟡 Medium
**該当**: `src/Models/StudyFilter.swift:81-118`, `src/Models/AnkiCard.swift:171-236`

`StudyFilterTarget` に15ケース、`StudyFilterConfig.filterCards` に14個の1行 `filter`、`AnkiCard` に14個の述語プロパティがあり、**3箇所が1対1で対応**しています。

```swift
// StudyFilter.swift — switch の中身がほぼ全部これ
case .studiedToday:              filtered = cards.filter { $0.isStudiedToday }
case .studiedYesterday:          filtered = cards.filter { $0.isStudiedYesterday }
case .wrongTriangleLastTime:     filtered = cards.filter { $0.isWrongTriangleLastTime }
// ... 14行
```

フィルタを1つ増やすには **enumケース + `description` + `switch`分岐 + `AnkiCard`のプロパティ**の4箇所を触る必要があります。どれか1つを忘れてもコンパイルは通ります（`switch` の網羅性チェックだけが唯一の防波堤です）。

また、`AnkiCard` にフィルタ専用の述語が14個ぶら下がることで、CLN-01 の肥大化にも寄与しています。

### 推奨対応

述語を enum 自身に持たせ、`switch` を1箇所に集約してください。

```swift
extension StudyFilterTarget {
    func matches(_ card: AnkiCard, on date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:            return true
        case .dueToday:       return card.review.lastStudiedAt == nil
                                  || calendar.startOfDay(for: card.review.dueDate) <= calendar.startOfDay(for: date)
        case .studiedToday:   return card.review.lastStudiedAt.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        // ...
        }
    }
}

public func filterCards(_ cards: [AnkiCard], currentDate: Date = Date()) -> [AnkiCard] {
    let matched = cards.lazy.filter { target.matches($0, on: currentDate) }
    return batchSize > 0 ? Array(matched.prefix(batchSize)) : Array(matched)
}
```

この形にすると [PERF-06](#perf-06)（件数だけ欲しい場面で配列を作らない）と [NEW-16](08-followup-review.md#new-16)（`currentDate` が一部にしか効かない）も同時に解決します。

---

<a id="cln-03"></a>

## CLN-03: `StudyFilterTarget` の `rawValue` が日本語の表示文字列であり、識別子を兼ねている

**深刻度**: 🟡 Medium
**該当**: `src/Models/StudyFilter.swift:4-28`, `src/Views/CourseDetailView.swift:257`

```swift
public enum StudyFilterTarget: String, ... {
    case dueToday = "今日が復習日のもの（推奨・SRS）"     // ← rawValue が UI 表示文字列
    ...
    public var id: String { self.rawValue }              // ← それが識別子でもある
}
```

表示テキストと識別子が結合しているため、次の問題があります。

- **UIの文言を変えると `id` が変わります**。`Picker` の選択状態や `ForEach` の差分計算に影響します
- 将来ローカライズする際（QA-07）、`rawValue` を `String(localized:)` にできません
- 実際にこの文字列が**デッキ名に混入**しています

```swift
let studyDeck = AnkiDeck(
    name: "\(course.title) (\(filterTarget.rawValue))",   // CourseDetailView.swift:257
    cards: cachedTargetCards
)
```

学習画面のタイトルが「英会話コース (今日が復習日のもの（推奨・SRS）)」となり、括弧が二重にネストして読みにくくなっています。

同じ問題が `CardFrontType`（`"問題"` / `"単語"` / `"穴埋め"`）と `CourseSortOption`（`"名前順"` 等）にもあります。

### 推奨対応

`rawValue` は安定した英数字の識別子にし、表示名を別プロパティにしてください。

```swift
public enum StudyFilterTarget: String, CaseIterable, Identifiable, Sendable {
    case dueToday, overdue, all, notMasteredFourTimes, unlearned  // ← 安定した識別子
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .dueToday: return "今日が復習日のもの（推奨・SRS）"
        ...
        }
    }
}
```

将来 `displayName` を `String(localized:)` に差し替えるだけで多言語化できます。

---

<a id="cln-04"></a>

## CLN-04: マジックナンバーが説明なしに散在している

**深刻度**: 🟡 Medium

| 値 | 場所 | 意味（コードからは読み取れない） |
|---|---|---|
| `1.3` / `2.5` / `0.05` / `0.2` / `0.1` / `0.5` | `SpacedRepetition.swift:29, 34, 38, 47` | SM-2 の ease 下限・上限・増減量 |
| `365` | `SpacedRepetition.swift:58` | 復習間隔の上限日数 |
| `1` / `4` | `SpacedRepetition.swift:49, 51` | SM-2 の初期間隔ラダー |
| `4` | `AnkiCard.swift:178` | 「完全習得」とみなす連続正解回数 |
| `30` | `AnkiCard.swift:184` | メンテナンス復習までの日数 |
| `90` / `1.5` | `CardStudyView.swift:136` | スワイプ確定の距離閾値・軸ロック比 |
| `500` / `2000` | `AddCardView.swift:359, 369, 376` | CSV の最大行数・セル最大文字数 |
| `3` | `DeckListView.swift:23` | 1ページあたりのコース数 |
| `240` / `190` | `DeckListView.swift:450` | コースカードの固定サイズ |
| `140` / `100` | `FlashcardView.swift:347` | 画像サムネイルの固定サイズ |

特に**SRSのパラメータが学習アルゴリズムの調整点そのもの**である点が問題です。「4回連続で習得」「30日でメンテナンス」は要件書に明記された仕様値ですが、コード上はただの数字リテラルで、仕様との対応が追えません。

### 推奨対応

意味のある名前を持つ定数にまとめてください。

```swift
public enum SRSParameters {
    /// SM-2 の ease factor の下限（SuperMemo 原典に準拠）
    public static let minimumEaseFactor = 1.3
    /// ease factor の上限。無制限だと復習間隔が指数的に発散するため設ける
    public static let maximumEaseFactor = 2.5
    /// 復習間隔の上限日数。これを超えると事実上出題されなくなる
    public static let maximumIntervalDays = 365
    /// 「完全習得」とみなす、日を跨いだ連続正解回数（要件 3.2-2）
    public static let masteryThreshold = 4
    /// 習得済みカードを再出題するまでの日数（エビングハウス忘却曲線対策）
    public static let maintenanceIntervalDays = 30
}
```

学習アルゴリズムのチューニングが1ファイルで完結し、値の根拠もコメントとして残ります。

---

<a id="cln-05"></a>

## CLN-05: 型で表現できる概念が文字列のまま扱われている

**深刻度**: 🟡 Medium

| プロパティ | 現在の型 | 問題 |
|---|---|---|
| `speechLanguage` | `String?` | `"en-US"` / `"ja-JP"` / `"es-ES"` の3値しか使われないのに、任意の文字列を代入できる。`EditCardView` の `Picker` がタグを手打ちしており、typo をコンパイラが検出できない |
| `themeColorHex` | `String` | `"#007AFF"` 形式の想定だが検証がない。そもそも描画に使われていない（UX-14） |
| `iconName` | `String` | SF Symbols 名。存在しない名前でも実行時まで分からない |
| 画像パス | `String` | `"CardImages/xxx.jpg"`（ローカル相対）と `"https://..."`（リモート）が同じ型で混在し、**参照するたびに `hasPrefix("http")` で分岐**している（`FlashcardView:363`, `ImageDetailView:26`, `ImageStore:32-36`） |

画像パスの扱いが特に問題で、**3箇所で同じ判別ロジックが繰り返され**、しかも `ImageStore.loadImage` はさらに `"/"` 始まりと `"file://"` 始まりの分岐も持っています。判別条件が場所ごとに微妙に違う（`hasPrefix("http")` と `hasPrefix("http://") || hasPrefix("https://")`）ため、片方だけ直すと不整合になります。

### 推奨対応

```swift
public enum CardImageRef: Codable, Hashable, Sendable {
    case local(fileName: String)     // Documents/CardImages/ 配下
    case remote(URL)                 // https のみ許可（SEC-02 の対応にもなる）
}

public enum SpeechLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en-US"
    case japanese = "ja-JP"
    case spanish = "es-ES"
    public var displayName: String { ... }
}
```

`CardImageRef` にすれば、分岐が `switch` 1箇所に集約され、追加時の漏れがコンパイラに検出されます。`https` 限定にすることで [SEC-02](05-security-and-privacy.md#sec-02)（スキーム未検証）も型レベルで解決します。

---

<a id="cln-06"></a>

## CLN-06: エラーが一律に握り潰されている

**深刻度**: 🟡 Medium

`os.Logger` が `DeckStore` に導入されたのは良い改善ですが、それ以外の箇所では `try?` による握り潰しが残っています。

| 箇所 | コード | 失われる情報 |
|---|---|---|
| `AddCardView.swift:232` | `if let path = try? ImageStore.saveImage(data: data)` | 保存失敗（容量不足等）が**ユーザーにも開発者にも伝わらない**。画像が黙って登録されない |
| `AddCardView.swift:231` | `try? await item.loadTransferable(...)` | 写真の読み込み失敗を検知できない |
| `AudioService.swift:33-34` | `try? AVAudioSession...setCategory/setActive` | 音が出ない原因が分からない |
| `FlashcardView.swift:317` | `guard let regex = try? NSRegularExpression(...)` | 実際には失敗しないが、失敗時は無言でマスクなし表示になる |

特に `ImageStore.saveImage` の失敗は、[PERF-05](#perf-05) の対応でダウンサンプリングを入れると**実際に失敗しうる処理**になります（不正な画像データ、メモリ不足）。今のうちにエラー経路を用意しておくべきです。

### 推奨対応

- ユーザー起因の操作（画像追加、CSV取り込み）は**必ず結果をUIに返す**（初回レビュー QA-08）
- 開発者向けには `Logger` に記録する。サブシステム/カテゴリは `DeckStore` と同じ規約で揃える

```swift
private let logger = Logger(subsystem: "com.ksk.kskAnki", category: "ImageStore")

do {
    let path = try ImageStore.saveImage(data: data)
    frontImageURLs.append(path)
} catch {
    logger.error("画像の保存に失敗: \(error.localizedDescription)")
    errorMessage = "画像を保存できませんでした。空き容量をご確認ください。"
}
```

---

<a id="cln-07"></a>

## CLN-07: `SettingsView` が任意依存 `DeckStore?` を持つ

**深刻度**: 🔵 Low
**該当**: `src/Views/SettingsView.swift:21-25, 54`

```swift
public let store: DeckStore?

public init(store: DeckStore? = nil) { self.store = store }
...
if let store = store {
    Section { Button("JSON バックアップを出力・コピー") { ... } }   // ← store がある時だけ現れる
}
```

依存を `Optional` にすると「画面の一部が黙って消える」という挙動になり、呼び出し側は**どの機能が使えるのかを型から読み取れません**。現在の呼び出しは `SettingsView(store: store)` の1箇所だけで、`nil` を渡すケースは存在しません。

### 推奨対応

```swift
public let store: DeckStore
public init(store: DeckStore) { self.store = store }
```

プレビュー用にインスタンスが必要なだけなら、`DeckStore` 側にプレビュー用のファクトリを用意してください。

---

<a id="cln-08"></a>

## CLN-08: 到達不能なコードとコメントの陳腐化

**深刻度**: 🔵 Low

[NEW-19](08-followup-review.md#new-19) で列挙した死にコードに加え、**実装と食い違うコメント**が残っています。

| 箇所 | コメント | 実態 |
|---|---|---|
| `DeckListView.swift:17` | `// フォルダフィルターステート (nil = すべて, UUID.nil = 未分類, 特定UUID = 各フォルダ)` | 「未分類」の状態は存在しない（UX-12 未対応） |
| `CardStudyView.swift:69` | `Text("... 上で △(惜しい)")` | 上スワイプは廃止済み（[NEW-11](08-followup-review.md#new-11)） |
| `ImageStore.swift:21` | `let fileName = "\(UUID().uuidString).jpg"` | 実際に書き込むのは HEIC の可能性が高い（[PERF-05](#perf-05)） |
| `SettingsView.swift:67, 72` | 「データバックアップ **& 復元**」 | 復元は未実装（[NEW-07](08-followup-review.md#new-07)） |

コードとコメントが食い違うと、コメントのほうが信用されて誤った修正を招きます。修正時にはコメントも同時に更新してください。

---

## 推奨する着手順

性能の3件は**実測で問題が確認できており、修正コストも小さい**ため最優先です。

| 順 | 対応 | 想定効果 | 規模 |
|---|---|---|---|
| 1 | [PERF-01](#perf-01) 統計画面の集計を1回化 + `DateFormatter` を `static` に | **1,042ms → 約10ms** | 小 |
| 2 | [PERF-03](#perf-03) セッション保存を1回にまとめる | **約1,959ms → 約100ms** | 小 |
| 3 | [PERF-02](#perf-02) `body` からの多重参照をやめ、集計値をキャッシュ | **54ms → 1ms未満** | 小〜中 |
| 4 | [RFC-04](#rfc-04) `CourseDetailView` の更新メソッド集約 | [NEW-10](08-followup-review.md#new-10) のバグも同時に解消 | 小 |
| 5 | [RFC-03](#rfc-03) パーサを型として抽出 | [NEW-04](08-followup-review.md#new-04) の再発防止、テスト可能に | 中 |
| 6 | [RFC-01](#rfc-01) 画像セクションの共通化 | 180行削減、修正箇所4→1 | 中 |
| 7 | [PERF-05](#perf-05) 画像のダウンサンプリング + キャッシュ | メモリ枯渇の回避 | 中 |
| 8 | [CLN-01](#cln-01) `AnkiCard` の責務分割 | **永続データが増える前に実施すべき** | 大 |

1〜3 はいずれも局所的な変更で、**合計3秒以上の主要なフリーズが解消**します。

> ⚠️ これらのリファクタリングに着手する前に、**[NEW-01](08-followup-review.md#new-01)（テストが1件も実行されていない）を必ず解消してください。** テストが動かない状態での構造変更は、デグレードを検出できないまま進むことになります。
