# 10. 追補レビュー②（[08] [09] 対応後の再検証）

- **レビュー日**: 2026-07-26（3回目）
- **対象**: [08. 追補レビュー](08-followup-review.md)（新規19件）および [09. 設計品質レビュー](09-cleancode-refactoring-performance.md)（25件）への対応後の全ソース（29ファイル）
- **検証方法**: 全ソース精読 + `swift build` / `swift test` / `scripts/run_tests.sh` の実行 + **ベンチマーク再計測** + **競合状態の再現実験**

> ⚠️ **レビュー中にソースが変更されました。**
> `src/Views/DeckListView.swift` がレビュー開始後の **23:18 に書き換えられ**、539行 → 285行になりました。本ドキュメントは**この変更後の状態**を反映していますが、この書き換えで**要件3.1の主要機能が4つ消失**しています（→ [NEW2-09](#new2-09)）。
> 変更はまだコミットされていません（`git status` で `M src/Views/DeckListView.swift`）。レビュー中も編集が続いている場合、本ドキュメントの内容が最新でない可能性があります。

---

## 総評

**前回指摘の重要な部分が正しく修正されています。** 特に以下は、指摘の意図を汲んだ良い対応です。

- **[NEW-02](08-followup-review.md#new-02)（学習ログがメイン動線で記録されない）が根本から解決されました。** `onRecordRating` コールバックを `CardStudyView` に追加し、コース経由・マイ単語帳経由の**両方が同じ `store.recordStudy()` を通る**設計になっています。責務を切り分けるという指摘どおりの修正です
- **[PERF-01](09-cleancode-refactoring-performance.md#perf-01) / [PERF-02](09-cleancode-refactoring-performance.md#perf-02) が実測で解消**しました。統計画面は1回の O(n) ループに集約、`streakDaysCount` / `todayStudiedCardsCount` は格納プロパティ化され、**18.02ms → 0.000ms** になりました
- **[NEW-01](08-followup-review.md#new-01)（テストが実行されない偽グリーン）に対し、`scripts/run_tests.sh` が正しくゲートするようになりました。** 意図的にアサーションを壊して検証したところ、**exit 1 で失敗を検出**しました。これは実質的な改善です
- [NEW-05](08-followup-review.md#new-05)（一括保存）、[NEW-06](08-followup-review.md#new-06)（Keychain の明示保存・削除）、[NEW-07](08-followup-review.md#new-07)（復元UI）、[NEW-11](08-followup-review.md#new-11)（スワイプ文言）、[QA-04](06-code-quality-and-testing.md#qa-04)（画像順序）、[RFC-01](09-cleancode-refactoring-performance.md#rfc-01)（`CardEditorFormView` 抽出）、[CLN-01](09-cleancode-refactoring-performance.md#cln-01)（`AnkiCard` の責務分割）も対応済みです

**一方で、修正の副作用として新たな問題が5件生じています。** うち2件は前回より深刻です。

1. **CIが常に失敗する状態になりました。** テストターゲットが `.testTarget` から `.executableTarget` に変更されたため、CIワークフローが実行する `swift test` は **`error: no tests found` で exit 1** を返します（実測）。ローカルの `run_tests.sh` は正しく動きますが、**CIは一度もテストを実行しません**
2. **非同期保存が競合し、実際にデータが失われることを再現しました。** `saveToDisk()` の `Task.detached` 化により、連続保存で**古いスナップショットが新しいものを上書き**します。4回試行して2回再現、最悪ケースでは**20回の更新のうち7回分が消失**しました
3. **`recordStudy()` が1判定あたり 39.3ms** かかります。`recalculateMetrics()` が毎回全ログ（14,600件）を再走査するためで、[PERF-02](09-cleancode-refactoring-performance.md#perf-02) の重い処理が「レンダリング経路」から「入力経路」へ移動した形です
4. **`.gitignore` が `*.xcodeproj` / `*.xcworkspace` を除外**しており、[BLK-01](01-blockers.md#blk-01) の修正（Xcodeプロジェクト作成）を**コミットできない**状態になりました
5. `saveToDisk()` が**常に `true` を返す**ため、検証コードの `assert(saveSuccess)` が意味を持ちません

なお **[BLK-01](01-blockers.md#blk-01)（iOSアプリターゲット不在）は3回連続で未対応**です。`.xcodeproj` / `Info.plist` / `Assets.xcassets` はいずれも存在せず、iOSアプリとしては依然として一度も起動できません。

---

## 対応状況サマリー

| 区分 | 08の19件 | 09の25件 | 合計 |
|---|---:|---:|---:|
| ✅ 完全対応 | 9 | 8 | 17 |
| ⚠️ 部分対応 | 2 | 3 | 5 |
| ❌ 未対応 | 8 | 14 | 22 |
| 🆕 新規指摘 | — | — | **9** |

---

## 📊 ベンチマーク再計測

前回と同一条件（**カード5,000枚 / 学習ログ14,600件**、release ビルド）で再計測しました。

| 計測対象 | 前回 | 今回 | 判定 |
|---|---:|---:|---|
| `store.streakDaysCount` | 18.02 ms | **0.000 ms** | ✅ 解消 |
| `store.todayStudiedCardsCount` | 18.07 ms | **0.000 ms** | ✅ 解消 |
| `StudyStatsView` の統計集計 | 125.73 ms ×8 | **1回のみ** | ✅ 解消 |
| `saveToDisk()`（呼び出し側の所要時間） | 84.12 ms | **0.003 ms** | ⚠️ 非同期化。ただし [NEW2-02](#new2-02) の競合を招いた |
| `saveToDisk(sync: true)` | ─ | 93.52 ms | 実処理コストは不変 |
| **`store.recordStudy()`（判定1回ごと）** | ─ | **39.30 ms** | 🆕 [NEW2-03](#new2-03) 新しいホットパス |
| `store.recalculateMetrics()` | ─ | 36.95 ms | 🆕 上記の内訳 |
| `filterCards(.dueToday)` | 6.41 ms | 6.95 ms | ❌ [PERF-06](09-cleancode-refactoring-performance.md#perf-06) 未対応 |

**トップ画面のレンダリングは 54ms → 1ms未満、統計画面は 1,042ms → 数ms になりました。** ここは明確な成果です。

---

# 🔴 新規の重大問題

<a id="new2-01"></a>

## NEW2-01: CIが常に失敗し、テストを一度も実行しない

**深刻度**: 🔴 Blocker
**該当**: `Package.swift:18-31`, `.github/workflows/test.yml:22-23`

[NEW-01](08-followup-review.md#new-01)（`canImport(XCTest)` によるサイレントスキップ）への対応として、テストが **XCTest から独自の実行可能ターゲットへ移行**されました。

```swift
// Package.swift — .testTarget ではなく .executableTarget になった
.executableTarget(
    name: "kskAnkiVerifier",
    dependencies: ["kskAnkiCore"],
    path: "tests"
)
```

`scripts/run_tests.sh` は `swift run kskAnkiVerifier` を実行するよう更新されています。しかし **CIワークフローは `swift test` のままです**。

```yaml
- name: Run swift test
  run: swift test --enable-code-coverage      # ← 更新されていない
```

**実測結果**:

```
$ swift test
Build complete! (0.13s)
error: no tests found; create a target in the 'Tests' directory
$ echo $?
1
```

パッケージにテストターゲットが1つも無いため、**CIは push のたびに必ず失敗し、しかも実際の検証は一度も走りません**。前回は「偽グリーン」でしたが、今回は「常時レッド ＋ 未実行」になりました。

なお `scripts/run_tests.sh` 自体は正しく機能することを確認しました。アサーションを意図的に壊して実行した結果:

```
kskAnkiVerifier/SpacedRepetitionTests.swift:13: Assertion failed: 【意図的に壊した検証】
❌ ERROR: Test suite failed or did not execute!
$ echo $?
1
```

**ゲートとしては正しく働いています。** 問題はCIがそれを呼んでいないことです。

### 推奨対応

CIワークフローを `run_tests.sh` に合わせてください。

```yaml
- name: Run test suite
  run: ./scripts/run_tests.sh
```

**ただし、XCTest を捨てた判断そのものを再考することを推奨します。** 現在の構成には以下の制約があります。

- `--enable-code-coverage` が使えず、**カバレッジが測定できません**
- Xcode のテストナビゲータに現れず、個別テストの実行やデバッグができません
- **最初のアサーション失敗でプロセスが停止**するため、1回の実行で1件しか失敗が分かりません
- `@testable import` は `-enable-testing` を要求するため、**release ビルドではコンパイル自体が失敗します**（実測: `swift run -c release kskAnkiVerifier` → `error: module 'kskAnkiCore' was not compiled for testing`）
- `assert` は最適化ビルドで除去される仕様のため、ビルド構成への依存が暗黙的です

`canImport(XCTest)` が false になる問題の本質は**このMacにフルXcodeが入っていないこと**であり、テストフレームワークの選択ではありません。Swift 6 なら **swift-testing がツールチェーンに同梱**されているため環境差が生じません。

```swift
import Testing
@testable import kskAnkiCore

@Suite("間隔反復スケジューラ")
struct SpacedRepetitionTests {
    @Test("△ 評価で復習間隔が短縮される")
    func doubtfulShortensInterval() {
        var card = AnkiCard(frontText: "Q", backText: "A", reps: 3, intervalDays: 10)
        card = SpacedRepetitionScheduler().processReview(card: card, rating: .doubtful)
        #expect(card.intervalDays < 10)      // 失敗しても後続のテストは走る
    }
}
```

---

<a id="new2-02"></a>

## NEW2-02: 非同期保存が競合し、古いデータが新しいデータを上書きする（再現済み）

**深刻度**: 🔴 Blocker（データ損失）
**該当**: `src/Services/DeckStore.swift:103-131`

[PERF-03](09-cleancode-refactoring-performance.md#perf-03)（保存でメインスレッドが固まる）への対応として `Task.detached` による非同期保存が導入されました。呼び出し側のコストは 84ms → 0.003ms になり、そこは成功しています。

しかし**書き込みの順序が保証されていません**。

```swift
public func saveToDisk(sync: Bool = false) -> Bool {
    let snapshot = DeckStoreSnapshot(...)      // ここでスナップショットを取る
    if sync { ... } else {
        Task.detached(priority: .utility) {     // ← 順序保証なしで並行実行
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: targetURL, options: [.atomic, .completeFileProtection])
        }
    }
    return true
}
```

`saveToDisk()` は**12箇所から呼ばれます**（`addFolder` / `addCourse` / `updateCourse` / `deleteCourse` / `toggleArchiveCourse` / `addCard` / `recordStudy` / `updateCard` / …）。学習セッション中は判定のたびに `recordStudy` → `saveToDisk()` が走るため、**複数の detached タスクが同一ファイルに並行して書き込みます**。`.atomic` は「1回の書き込みが中途半端にならない」ことしか保証せず、**タスクの完了順序は保証しません**。

### 再現実験

20回の状態更新を連続で行い、各回で `saveToDisk()` を発火させ、全タスク完了後にディスクの内容を確認しました。

```
■ 非同期 saveToDisk() の競合検証
  最終的なメモリ上の状態: STATE-20

  試行1: 実際にディスクへ残った状態: STATE-20  → 一致
  試行2: 実際にディスクへ残った状態: STATE-19  → ❌ 不一致（1回分が消失）
  試行3: 実際にディスクへ残った状態: STATE-13  → ❌ 不一致（7回分が消失）
  試行4: 実際にディスクへ残った状態: STATE-20  → 一致
```

**4回中2回で、古いスナップショットが新しいものを上書きしました。** 最悪のケースでは20回の更新のうち7回分が失われています。

実際のアプリでは「学習セッションの判定が数枚ぶん消える」「カードを追加した直後にアプリを終了すると追加が消える」という形で現れます。タイミング依存のため再現性が低く、**発生してもユーザーは原因に気づけません**。

### 推奨対応

書き込みを**直列化**してください。専用のアクターを設ければ順序が保証されます。

```swift
private actor PersistenceWriter {
    private let url: URL
    init(url: URL) { self.url = url }

    func write(_ snapshot: DeckStoreSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            logger.error("保存に失敗: \(error.localizedDescription)")
        }
    }
}

// DeckStore 側
private let writer: PersistenceWriter

public func saveToDisk() {
    let snapshot = DeckStoreSnapshot(...)
    Task { await writer.write(snapshot) }     // アクターが直列化を保証する
}
```

さらに、[PERF-03](09-cleancode-refactoring-performance.md#perf-03) で提案した**デバウンス**（変更後0.5秒待ってまとめて書く）を併用すると、書き込み回数そのものが激減し、競合の機会も減ります。

**アプリ終了時のフラッシュ**も必要です。現状は `scenePhase` の監視が無いため、バックグラウンド移行直後に終了されると未完了の書き込みが失われます。

---

# 🟠 新規の高深刻度問題

<a id="new2-03"></a>

## NEW2-03: 判定1回ごとに 39.3ms かかる新しいホットパスが生まれた

**深刻度**: 🟠 High
**該当**: `src/Services/DeckStore.swift:45-74, 198-203`

[PERF-02](09-cleancode-refactoring-performance.md#perf-02) の対応で、集計は計算プロパティから格納プロパティ + `recalculateMetrics()` に変わりました。読み取りは 18ms → 0.000ms になり、レンダリング経路の問題は解消しています。

しかし `recalculateMetrics()` の中身は**以前と同じ全ログ走査**です。

```swift
public func recalculateMetrics() {
    self.todayStudiedCardsCount = studyLogs.filter { calendar.isDateInToday($0.studiedAt) }.count
    let studyDates = Set(studyLogs.map { calendar.startOfDay(for: $0.studiedAt) })   // 全ログぶん
    ...
}
```

そして `recordStudy()` が**毎回これを呼びます**。

```swift
public func recordStudy(cardId: UUID, rating: Rating, at date: Date = Date()) {
    studyLogs.append(log)
    recalculateMetrics()     // ← 36.95 ms（実測）
    saveToDisk()
}
```

`recordStudy` は `onRecordRating` 経由で **◯/△/✕ の判定1回ごとに呼ばれます**（[NEW-02](08-followup-review.md#new-02) の修正で正しくそうなりました）。

**実測: `recordStudy()` 1回 = 39.30 ms。**

`REQUIREMENTS.md 3.3-①` は「1枚1秒のテンポでスピーディーに正誤判定」を掲げていますが、**判定ボタンを押すたびに約39msのひっかかり**が生じます。しかもこれは**学習ログが増えるほど線形に悪化**します（5年利用なら約100ms）。

問題は、**ログを1件追加しただけなのに14,600件すべてを再集計している**ことです。

### 推奨対応

追加された1件だけを見て差分更新してください。全走査は起動時の1回で十分です。

```swift
public func recordStudy(cardId: UUID, rating: Rating, at date: Date = Date()) {
    studyLogs.append(StudyLog(cardId: cardId, rating: rating, studiedAt: date))

    // 差分更新: O(1)
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: date)
    if calendar.isDateInToday(date) { todayStudiedCardsCount += 1 }
    if studyDays.insert(day).inserted {          // 学習日のSetをメンバとして保持しておく
        streakDaysCount = computeStreak(from: studyDays)   // 日数ぶんのループのみ
    }

    saveToDisk()
}
```

`studyDays: Set<Date>` をメンバとして保持すれば、`recalculateMetrics()` の全走査は初期化時とインポート時だけになります。[NEW-17](08-followup-review.md#new-17)（ログの日次集計化）を実施すれば、さらに根本的に解決します。

---

<a id="new2-04"></a>

## NEW2-04: `.gitignore` が Xcode プロジェクトを除外しており、BLK-01 の修正をコミットできない

**深刻度**: 🟠 High
**該当**: `.gitignore:7-10`

[QA-03](06-code-quality-and-testing.md#qa-03) への対応で `.build/` と `.swiftpm/` が追加されたのは正しい修正です（`git ls-files` で `.build/` の混入0件を確認しました）。

しかし同時に、**バージョン管理すべきものまで除外されています**。

```gitignore
# Swift Build & Package Manager
.build/
.swiftpm/
*.xcodeproj        # ← Xcodeプロジェクトが永久にコミットできない
*.xcworkspace      # ← 同上
```

`*.xcodeproj` は、XcodeGen や Tuist で**プロジェクトファイルを自動生成している場合にのみ**無視すべきものです。このリポジトリには `project.yml` も `Project.swift` も存在しません。

つまり現状は、**[BLK-01](01-blockers.md#blk-01) を修正して iOS アプリターゲットを作っても、それをリポジトリに追加できません**。3回のレビューで最優先に挙げ続けているブロッカーの、修正経路自体が塞がれた形です。

### 推奨対応

除外するのはユーザー固有の設定だけにしてください。

```gitignore
# Swift Build & Package Manager
.build/
.swiftpm/

# Xcode（プロジェクトファイル本体はコミットする）
xcuserdata/
*.xcuserstate
*.xcscmblueprint
DerivedData/
```

---

<a id="new2-05"></a>

## NEW2-05: `saveToDisk()` が常に `true` を返し、検証が空振りしている

**深刻度**: 🟠 High
**該当**: `src/Services/DeckStore.swift:102-131`, `tests/DeckStoreTests.swift:28-29`

戻り値が実態と一致していません。

```swift
@discardableResult
public func saveToDisk(sync: Bool = false) -> Bool {
    if sync {
        do { ... } catch { logger.error(...) }     // ← 失敗しても抜けるだけ
    } else {
        Task.detached { ... }                       // ← 完了を待たない
    }
    return true                                     // ← 無条件で true
}
```

- **同期パスで書き込みが失敗しても `true`** を返します（容量不足・権限エラーなど）
- **非同期パスは完了前に `true`** を返します。成否は原理的に分かりません

この結果、検証コードのアサーションが**永久に成功する空振り**になっています。

```swift
// tests/DeckStoreTests.swift:28
let saveSuccess = store.saveToDisk(sync: true)
assert(saveSuccess, "Diskへの保存が成功すること")     // ← 絶対に失敗しない
```

「保存に失敗する」という最も重要な異常系が、テストされているように見えて実際は検証されていません。

### 推奨対応

同期パスは実際の結果を返し、非同期パスは `Bool` を返さないようシグネチャを分けてください。

```swift
/// 同期保存。成否を返す
public func saveToDiskSync() -> Bool {
    do {
        let data = try JSONEncoder().encode(snapshot())
        try data.write(to: saveFileURL, options: [.atomic, .completeFileProtection])
        return true
    } catch {
        logger.error("保存に失敗: \(error.localizedDescription)")
        return false
    }
}

/// 非同期保存。結果を返さない（戻り値で誤解を生まない）
public func scheduleSave() { ... }
```

検証側も、**書き込み不可能なパスを指定して `false` が返ること**を確認するテストを追加してください。そのためにも保存先の注入（[NEW-14](08-followup-review.md#new-14)）が必要です。

---

# 🟡 新規の中深刻度問題

<a id="new2-06"></a>

## NEW2-06: バックアップ復元後に統計値が古いまま残る

**深刻度**: 🟡 Medium
**該当**: `src/Services/BackupService.swift:28-40`

[NEW-07](08-followup-review.md#new-07) への対応で復元機能が実装されたのは良い改善です（`SettingsView.swift:246` から `importBackupJSON` が呼ばれることを確認しました）。

しかし復元後に `recalculateMetrics()` が呼ばれていません。

```swift
store.folders = snapshot.folders
store.courses = snapshot.courses
store.studyLogs = snapshot.studyLogs          // ← ログを丸ごと差し替え
store.dailyGoalCardsCount = snapshot.dailyGoalCardsCount
store.saveToDisk()
return true                                    // ← recalculateMetrics() が無い
```

`streakDaysCount` / `todayStudiedCardsCount` は [PERF-02](09-cleancode-refactoring-performance.md#perf-02) の対応で**格納プロパティ**になったため、明示的に再計算しない限り更新されません。

機種変更時にバックアップから復元しても、**トップ画面のストリークと本日枚数は復元前の値（多くは0）のまま**になります。アプリを再起動すれば `init` 内の `recalculateMetrics()` で正しくなりますが、ユーザーには「復元が失敗した」ように見えます。

### 推奨対応

```swift
store.studyLogs = snapshot.studyLogs
store.dailyGoalCardsCount = snapshot.dailyGoalCardsCount
store.recalculateMetrics()      // ← 追加
store.saveToDisk()
```

より根本的には、`studyLogs` を `private(set)` にして変更経路を `recordStudy` / `replaceAll` に限定すれば、この種の同期漏れが起きなくなります。

---

<a id="new2-07"></a>

## NEW2-07: 復元ボタンが無言でシステムのクリップボードを読む

**深刻度**: 🟡 Medium
**該当**: `src/Views/SettingsView.swift:102-106`

```swift
Button(action: {
    #if canImport(UIKit)
    if let pasteStr = UIPasteboard.general.string, pasteStr.contains("courses") {
        restoreInputJSON = pasteStr           // ← ボタンを押すと即座に読み取る
    }
    #endif
    isImportSheetPresented = true
})
```

iOS 16 以降、`UIPasteboard.general.string` へのプログラムからのアクセスは**「〜にペーストを許可しますか？」というシステム警告**を表示します。ユーザーは復元シートを開こうとしただけなのに、意図しない権限ダイアログに直面します。

また、クリップボードに機微な内容（他アプリからコピーしたパスワード等）がある状態で押すと、**アプリがそれを読み取ろうとした**という記録が残ります。

出力側 [NEW-07](08-followup-review.md#new-07) で指摘した「全学習データを無言でクリップボードにコピー」も、`SettingsView.swift:90` に残っています。

### 推奨対応

システムが提供する明示的なペースト UI を使ってください。ユーザーの操作が伴うため権限警告が出ません。

```swift
// 貼り付け: PasteButton はユーザーのタップが権限になる
PasteButton(payloadType: String.self) { strings in
    restoreInputJSON = strings.first ?? ""
}

// 書き出し: クリップボードではなくファイル共有
ShareLink(item: backupJSONText, preview: SharePreview("kskAnki バックアップ"))
```

---

<a id="new2-08"></a>

## NEW2-08: `@main` が到達不能なコードとして残っている

**深刻度**: 🟡 Medium
**該当**: `src/App/kskAnkiApp.swift:15-27`

[NEW-03](08-followup-review.md#new-03)（エントリポイントが未コンパイル）への対応として、`exclude: ["App"]` が撤廃され `kskAnkiAppView` が公開ビューとして切り出されました。これは正しい方向です。ビルドログでも `Compiling kskAnkiCore kskAnkiApp.swift` を確認しました。

ただし `@main` 側は条件コンパイルで囲われています。

```swift
#if !SWIFT_PACKAGE
@available(iOS 17.0, macOS 14.0, *)
@main
struct kskAnkiApp: App { ... }
#endif
```

**`SWIFT_PACKAGE` は SwiftPM がビルドする際に常に定義されます。** このファイルは `kskAnkiCore` パッケージ内にあるため、Xcode のアプリターゲットからパッケージとして参照した場合も `SWIFT_PACKAGE` は定義されます。つまり **`@main struct kskAnkiApp` はどのような構成でもコンパイルされません**。

`kskAnkiAppView` を用意した以上、アプリターゲット側で以下を書くのが正しい形であり、パッケージ内の `@main` は不要です。

```swift
// アプリターゲット側（Xcodeプロジェクト内）に置く
@main
struct kskAnkiApp: App {
    var body: some Scene { WindowGroup { kskAnkiAppView() } }
}
```

### 推奨対応

`#if !SWIFT_PACKAGE` ブロックを削除し、`kskAnkiAppView` のみをパッケージに残してください。`@main` は [BLK-01](01-blockers.md#blk-01) で作成するアプリターゲット側に置きます。到達不能なコードを残すと「エントリポイントは存在する」という誤解を招きます。

---

<a id="new2-09"></a>

## NEW2-09: `DeckListView` の書き換えで、要件3.1の主要機能が4つ消失した

**深刻度**: 🔴 Blocker（要件リグレッション）
**該当**: `src/Views/DeckListView.swift`（未コミット、23:18 の変更）

レビュー中に `DeckListView.swift` が 539行 → 285行に書き換えられました。整理自体は歓迎すべきことですが、**`REQUIREMENTS.md 3.1` が要求する機能が削除**されています。

```
$ for k in CourseSortOption sortedCourses isArchived toggleArchiveCourse contextMenu currentPage pageSize; do
    echo -n "  $k: "; grep -c "$k" src/Views/DeckListView.swift; done
  CourseSortOption:     0
  sortedCourses:        0
  isArchived:           0
  toggleArchiveCourse:  0
  contextMenu:          0
  currentPage:          0
  pageSize:             0
```

失われた機能と、対応する要件は次のとおりです。

| 要件 | 内容 | 現状 |
|---|---|---|
| 3.1 ソート機能 | 名前順 / 一番最近学習した順 / 更新日順 | ❌ 並べ替えUIが消失。`filteredCourses` をそのまま表示 |
| 3.1 ページネーション | コース数が多い場合は1ページ3件ずつ表示 | ❌ 消失 |
| 3.1 コースのアーカイブ & 復元 | 長押し / コンテキストメニューから実行 | ❌ 消失。`contextMenu` 自体が無い |
| 3.1 アクティブ/アーカイブ済みの切替表示 | トップ画面でのセグメント切替 | ❌ 消失 |

副作用として、**コースの削除手段も無くなりました**（削除はコンテキストメニューにのみ存在していたため）。

モデル層とストア層の実装は残っており、**参照されない死にコード**になっています。

```
$ grep -rln "CourseSortOption\|toggleArchiveCourse" src/
src/Models/Course.swift          ← 定義のみ
src/Services/DeckStore.swift     ← 定義のみ（Viewからの呼び出し0件）
```

`Course.isArchived` フラグも同様に、値を変更する経路が存在しなくなりました。アーカイブ済みのコースが既にあるユーザーは、**そのコースを永久に復元できません**（`filteredCourses` が `isArchived` を見ていないため、アーカイブ済みコースも一覧に混ざって表示されます）。

### 推奨対応

削除された4機能を戻してください。行数削減が目的なら、機能を落とすのではなく**コンポーネントに切り出す**のが正しい方向です（[RFC-06](09-cleancode-refactoring-performance.md#rfc-06) で `FlashcardView` について提案したのと同じ方針）。

```
CourseListSection   … フォルダチップ + ソート + ページャ + コースカード
StudyStreakHeader   … ストリーク・日次目標
DeckListSection     … マイ単語帳
```

**リファクタリングで機能が落ちたことを検出できなかった点が、より重要な問題です。** [NEW2-01](#new2-01) でCIがテストを実行していないため、こうした要件レベルのリグレッションを機械的に検出する手段がありません。まずCIを復旧させてください。

なお、この変更により以下の既存指摘は状況が変わりました。

- [UX-11](04-ui-ux-accessibility.md#ux-11)（コース削除に確認がない）→ **削除機能ごと消失**したため、機能を戻す際に確認ダイアログも併せて実装してください
- [UX-13](04-ui-ux-accessibility.md#ux-13)（ページ番号がクランプされない）→ **ページャごと消失**。同上

---

## ✅ 今回の対応で解消が確認できたもの

| ID | 内容 | 確認方法 |
|---|---|---|
| [NEW-02](08-followup-review.md#new-02) | 学習ログの記録経路統一 | `onRecordRating` が `CourseDetailView` / `DeckListView` の両方から `store.recordStudy` を呼ぶことをコードで確認 |
| [NEW-05](08-followup-review.md#new-05) | セッション保存の一括化 | `updateCardsInDeckBulk` / `updateCardsInCourseBulk` で保存1回に集約 |
| [NEW-06](08-followup-review.md#new-06) | Keychain の保存タイミング | 明示的な保存・削除ボタンに変更（`SettingsView.swift:229, 236`） |
| [NEW-07](08-followup-review.md#new-07) | バックアップ復元 | 復元UIと `importBackupJSON` の接続を確認（→ [NEW2-06](#new2-06) [NEW2-07](#new2-07) は残課題） |
| [NEW-11](08-followup-review.md#new-11) | スワイプ文言の不整合 | 「上で △」の記述が消えたことを確認 |
| [NEW-14](08-followup-review.md#new-14) | ─ | 未対応（保存先が注入不可のまま） |
| [PERF-01](09-cleancode-refactoring-performance.md#perf-01) | 統計画面 1,042ms | 1回の O(n) ループ + `.task` でのキャッシュ化。`DateFormatter` も `Date.formatted` に置換 |
| [PERF-02](09-cleancode-refactoring-performance.md#perf-02) | トップ画面 54ms | **実測 0.000 ms**（→ ただし [NEW2-03](#new2-03) へ移動） |
| [PERF-03](09-cleancode-refactoring-performance.md#perf-03) | セッション終了 2秒 | 一括化 + 非同期化（→ ただし [NEW2-02](#new2-02) の競合を招いた） |
| [RFC-01](09-cleancode-refactoring-performance.md#rfc-01) | Add/Edit の180行重複 | `CardEditorFormView` として抽出（`EditCardView` は 297→140行） |
| [RFC-04](09-cleancode-refactoring-performance.md#rfc-04) | 更新メソッドの重複 | `updateCardsInCourseBulk` に集約 |
| [CLN-01](09-cleancode-refactoring-performance.md#cln-01) | `AnkiCard` の責務分割 | `CardStudyMetrics` / `CardDetails` に分割。既存コード互換のため転送プロパティを維持 |
| [QA-03](06-code-quality-and-testing.md#qa-03) | `.gitignore` | `.build/` の混入0件を確認（→ ただし [NEW2-04](#new2-04)） |
| [QA-04](06-code-quality-and-testing.md#qa-04) | 画像順序の崩れ | `Array(Set(...))` が全廃されたことを確認 |

---

## ❌ 3回のレビューを通じて未対応のまま残っている指摘

| ID | 深刻度 | 内容 | 状況 |
|---|---|---|---|
| [BLK-01](01-blockers.md#blk-01) | 🔴 | iOSアプリターゲット不在 | **3回連続で未対応**。`.xcodeproj` / `Info.plist` / `Assets.xcassets` すべて無し。加えて [NEW2-04](#new2-04) で修正経路も塞がれた |
| [NEW-08](08-followup-review.md#new-08) | 🟠 | 表面の朗読ボタンが `question` / `cloze` で消失 | 表面ヘッダーに朗読ボタン無し（要件3.7違反） |
| [NEW-09](08-followup-review.md#new-09) | 🟠 | コンテンツ一覧のカテゴリーバッジ消失 | `CourseContentView.cardRow` に `categoryPath` 無し（要件3.8違反） |
| [NEW-12](08-followup-review.md#new-12) | 🟡 | カード切替で `isEditingNotes` が解除されない | `onChange(of: card.id)` は `noteText` / `showHint` のみリセット |
| [NEW-13](08-followup-review.md#new-13) | 🟡 | `backText` が空でも解答ブロックを表示 | `Text(card.backText)` にガード無し（要件3.5違反） |
| [NEW-14](08-followup-review.md#new-14) | 🟡 | テストが実 `~/Documents` を汚染 | 保存先が注入不可のまま。実際に `kskAnki_store.json` が生成されることを確認 |
| [NEW-17](08-followup-review.md#new-17) | 🟡 | `studyLogs` が無制限に増加 | [NEW2-03](#new2-03) の直接原因 |
| [UX-09](04-ui-ux-accessibility.md#ux-09) | 🔵 | 進捗バーが1枚目で100% | `ProgressView(value: Double(current))` のまま |
| [UX-11](04-ui-ux-accessibility.md#ux-11) | 🟡 | コース削除に確認ダイアログ無し | 永続化が効いている今、実際にデータが消える |
| [UX-12](04-ui-ux-accessibility.md#ux-12) | 🟡 | 「未分類」を絞り込めない | 実装と食い違うコメントもそのまま |
| [UX-13](04-ui-ux-accessibility.md#ux-13) | 🟡 | ページ番号がクランプされない | |
| [UX-14](04-ui-ux-accessibility.md#ux-14) | 🟡 | テーマカラー未使用・日付未表示 | `themeColorHex` は保存のみ、`Color.blue` 固定 |
| [UX-15](04-ui-ux-accessibility.md#ux-15) / [NEW-04](08-followup-review.md#new-04) | 🟠 | 穴埋めの `[...]` 誤爆・複数空欄で誤った頭文字 | ─ |
| [SEC-02](05-security-and-privacy.md#sec-02) | 🟡 | URLスキーム未検証・ATS | `AudioService` は4回のレビューを通じて**一度も変更されていません** |
| [SEC-03](05-security-and-privacy.md#sec-03) | 🟡 | `AVAudioSession` を解放しない・消音無視 | 同上（`setActive(false)` 無し） |
| [QA-05](06-code-quality-and-testing.md#qa-05) | 🟡 | 言語自動判定が粗い | 同上（`NLLanguageRecognizer` 未導入） |
| [PERF-05](09-cleancode-refactoring-performance.md#perf-05) | 🟠 | 画像がフルサイズでデコード・キャッシュ無し | `ImageStore` にダウンサンプリング無し。`body` から毎回デコード |
| [PERF-06](09-cleancode-refactoring-performance.md#perf-06) | 🟡 | 件数取得のための配列コピー | `lazy` 未導入。実測 6.95ms |
| [CLN-04](09-cleancode-refactoring-performance.md#cln-04) | 🟡 | マジックナンバーの散在 | `SRSParameters` 未作成 |
| [RFC-08](09-cleancode-refactoring-performance.md#rfc-08) | 🟡 | 背景色ヘルパーが5箇所に重複 | `Theme.swift` 未作成。5箇所のまま |

> **`src/Services/AudioService.swift` は初回レビューから一度も変更されていません。** SEC-02 / SEC-03 / QA-05 の3件がこのファイルに集中しています。ファイル単位で対応リストから漏れている可能性が高いので、次回まとめて着手してください。

---

## 次のアクション（優先順）

| 順 | 対応 | 理由 |
|---|---|---|
| 1 | [NEW2-09](#new2-09) `DeckListView` の消失機能（ソート・ページャ・アーカイブ・削除）を復旧 | **要件3.1の機能が4つ失われています。** 未コミットのうちに戻すのが最も安全 |
| 2 | [NEW2-02](#new2-02) 保存の直列化（アクター導入） | **データ損失が実際に再現しています** |
| 3 | [NEW2-01](#new2-01) CIを `run_tests.sh` に切り替え | 常時レッドで検証を一度も実行しておらず、[NEW2-09](#new2-09) のようなリグレッションを検出できません |
| 4 | [NEW2-04](#new2-04) `.gitignore` から `*.xcodeproj` を削除 | これを直さないと次項に着手できません |
| 5 | [BLK-01](01-blockers.md#blk-01) Xcodeプロジェクト作成（要Xcodeインストール） | 3回連続の最優先未対応。**アプリとして一度も起動できていません** |
| 6 | [NEW2-03](#new2-03) `recordStudy` の差分更新化 | 判定ごとの39msは体感に直結し、今後悪化します |
| 7 | [NEW2-05](#new2-05) `saveToDisk` の戻り値を実態に合わせる | 異常系のテストが空振りしています |
| 8 | [NEW-08](08-followup-review.md#new-08) / [NEW-09](08-followup-review.md#new-09) / [NEW-13](08-followup-review.md#new-13) リグレッション3件 | いずれも数行の修正で要件を満たせます |
| 9 | `AudioService` の3件（SEC-02 / SEC-03 / QA-05）をまとめて | ファイルごと未着手のため |

**進捗は着実です。** 17件が完全に解消し、性能上の主要な3つのボトルネックは実測で消えました。残る課題の中心は「[BLK-01] を進めるための環境（Xcodeのインストール）」と、「修正の副作用を検出する仕組み（CIとテスト）」の2点に集約されています。この2つが整えば、以降の修正サイクルは大幅に速く・安全になります。
