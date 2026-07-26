# 12. 最終確認（全指摘の対応状況）

- **確認日**: 2026-07-27
- **確認対象**: これまでの全レビュー（[01](01-blockers.md)〜[11](11-followup-review-3.md)）で挙げた全指摘
- **確認方法**: クリーンビルド + `scripts/run_tests.sh` + **ベンチマーク再計測** + **再現テストの再実行** + 全ソースの該当箇所確認

---

## 結論

**「すべて修正済み」ではありません。** 今回のラウンドで9件が新たに解消しましたが、**6件が未対応、3件が部分対応のまま**残っています。

特に **[BLK-01](01-blockers.md#blk-01)（iOSアプリターゲット不在）は初回レビューから5回連続で未対応**で、この状態では**iOSアプリとして一度も起動できません**。他の指摘がすべて直っても、アプリが動かないという最も重要な事実は変わりません。

---

## ✅ 今回のラウンドで解消を確認できたもの（9件）

すべて実測またはコード確認で検証しました。

| ID | 内容 | 検証結果 |
|---|---|---|
| [NEW3-01](11-followup-review-3.md#new3-01) | サンプルデータ復活の再発 | **再現テストで解消を確認**（下記） |
| [NEW3-02](11-followup-review-3.md#new3-02) | `updateCourse()` の不要な全走査 | **実測 35.75 ms → 0.001 ms** |
| [NEW3-03](11-followup-review-3.md#new3-03) | ダウンサンプリングAPIが未配線 | `FlashcardView.swift:396` で `loadDownsampledImage` を使用（フォールバック付き） |
| [NEW-12](08-followup-review.md#new-12) | カード切替で編集モードが解除されない | `FlashcardView.swift:261` に `isEditingNotes = false` を追加 |
| [NEW-13](08-followup-review.md#new-13) | `backText` が空でも解答ブロックを表示 | `FlashcardView.swift:130` に `isEmpty` ガードを追加 |
| [NEW-14](08-followup-review.md#new-14) | 保存先が注入できずテストが実環境を汚染 | `DeckStore(storageURL: URL? = nil)` を追加。本確認でも一時ディレクトリを使用 |
| [UX-09](04-ui-ux-accessibility.md#ux-09) | 進捗バーが1枚目で100% | 呼び出しが `progressHeader(current: currentIndex, ...)` に変更され、0始まりに |
| [UX-14](04-ui-ux-accessibility.md#ux-14) | テーマカラーが描画に使われない | `Color(hex:)` を追加し、`DeckListView.swift:352, 386` で使用 |
| [SEC-02](05-security-and-privacy.md#sec-02) | URLスキームを検証しない | `AudioService.swift:59-61` で `http` / `https` / `file` に限定 |

### 再現テストの結果

```
■ NEW3-01 サンプルデータ復活の再現テスト
  ① 初回起動: コース2件
  ② 全削除:   コース0件
  ③ 再起動:   コース0件
  ✅ 空のまま（NEW3-01 解消）
```

### ベンチマーク（カード5,000枚 / 学習ログ14,600件）

| 計測対象 | 前回 | 今回 |
|---|---:|---:|
| `updateCourse()` | 35.75 ms | **0.001 ms** |
| `recordStudy()` | 0.059 ms | 0.050 ms |
| `streakDaysCount` 読み取り | 0.000 ms | 0.000 ms |
| `filterCards(.dueToday)` | 6.65 ms | 6.65 ms（[PERF-06](09-cleancode-refactoring-performance.md#perf-06) 未対応） |

ビルドは警告0・エラー0、検証スイート12件はすべて成功しています。

---

## ❌ 未対応（6件）

<a id="open-blk-01"></a>

### 1. [BLK-01](01-blockers.md#blk-01) — iOSアプリターゲットが存在しない 🔴

**初回レビューから5回連続で未対応。最も重要な指摘です。**

```
$ find . -name '*.xcodeproj' -not -path './.build/*'
（該当なし）
```

見つかるのは `.swiftpm/xcode/package.xcworkspace` のみで、これは SwiftPM がパッケージ編集用に自動生成するもので、**アプリターゲットではありません**。

部品は揃っています。

| 項目 | 状態 |
|---|---|
| `src/App/Info.plist` | ✅ 作成済み |
| `src/App/Assets.xcassets` | ✅ 作成済み |
| `kskAnkiAppView`（公開ビュー） | ✅ 実装済み |
| `.gitignore` / `Package.swift` の設定 | ✅ 対応済み |
| **`.xcodeproj` とアプリターゲット** | ❌ **未作成** |

**現状、`Info.plist` も `Assets.xcassets` も、どのビルドからも参照されていないファイルです。** これらを束ねるアプリターゲットが無い限り、iPhone でもシミュレータでもアプリは起動しません。

このMacにはフルXcodeがインストールされていないため（`xcrun --show-sdk-path` が Command Line Tools を指しています）、**Xcodeのインストールが前提**になります。これは `canImport(XCTest)` が false になり XCTest を使えない原因でもあります。

### 2. [UX-12](04-ui-ux-accessibility.md#ux-12) — 「未分類」フォルダを絞り込めない 🟡

```
$ grep -c "未分類\|unfiled\|folderId == nil" src/Views/DeckListView.swift
0
```

`CreateCourseView` は「未分類 (フォルダなし)」を選択肢として提供していますが、トップ画面には対応するチップがなく、`folderId == nil` のコースは「すべて」でしか見られません。

### 3. [PERF-06](09-cleancode-refactoring-performance.md#perf-06) — 件数取得のための配列コピー 🟡

`filterCards` は件数表示にしか使わない場面でも `[AnkiCard]` を丸ごと生成します（実測 6.65 ms）。`lazy` の導入は未着手です。

### 4. [CLN-04](09-cleancode-refactoring-performance.md#cln-04) — マジックナンバーの散在 🟡

```
$ grep -rn "SRSParameters" src/
（該当なし）
```

`1.3` / `2.5` / `365` / `4` / `30`（SRSパラメータ）、`90` / `1.5`（スワイプ閾値）、`500` / `2000`（CSV上限）などが直接リテラルのままです。要件書に明記された仕様値とコードの対応が追えません。

### 5. [NEW-17](08-followup-review.md#new-17) — `studyLogs` が無制限に増加 🟡

上限・集約・削除のロジックがありません。保存のたびに全件がJSONエンコードされます。

### 6. [QA-07](06-code-quality-and-testing.md#qa-07) — i18n未対応 🔵

全UI文字列が日本語リテラルの直書きのままです。日本語専用として進めるなら優先度は低い項目です。

---

## ⚠️ 部分対応（3件）

### 1. [RFC-08](09-cleancode-refactoring-performance.md#rfc-08) — 背景色ヘルパーの重複

`src/Views/Theme.swift` が新規作成されましたが、**中身は `Color(hex:)` のみ**で、これは [UX-14](04-ui-ux-accessibility.md#ux-14) への対応です。指摘した重複そのものは残っています。

```
$ grep -rn "private var cardBgColor\|private var backgroundColor\|private var frontBgColor" src/Views/
DeckListView.swift:407:   private var backgroundColor: Color {
DeckListView.swift:415:   private var cardBgColor: Color {
FlashcardView.swift:460:  private var frontBgColor: Color {
FlashcardView.swift:468:  private var cardBgColor: Color {
StudyStatsView.swift:246: private var backgroundColor: Color {
StudyStatsView.swift:254: private var cardBgColor: Color {
```

**6箇所の重複が3ファイルに残ったままです。** `Theme.swift` という置き場所ができたので、移すだけで完了します。

### 2. [NEW2-05](10-followup-review-2.md#new2-05) — `saveToDisk` の戻り値

`saveToDiskSync()` が実際の成否を返すようになったのは正しい修正です。ただし非同期版は依然として無条件で `true` を返します。

```swift
Task { await writer.write(snapshot) }
return true                            // ← 完了前に必ず true
```

`@discardableResult -> Bool` というシグネチャが実態と一致していません。非同期版は `Bool` を返さない形にするのが素直です。

### 3. [NEW2-07](10-followup-review-2.md#new2-07) — クリップボード操作

シートを開いた瞬間の自動読み取りは解消され、明示的なボタン操作になりました（主要な問題は解決）。ただし依然として `UIPasteboard.general.string` を直接読むため、iOS 16+ のペースト許可ダイアログが表示されます。`PasteButton` に置き換えれば不要になります。書き出し側（`SettingsView.swift:90`）も全学習データをクリップボードへコピーしたままです。

---

## 補足: 要件書の更新が必要な箇所（実装が正しく、仕様書が古い）

| 箇所 | 内容 |
|---|---|
| `REQUIREMENTS.md 1` | 技術スタックに「Combine」とあるが、使用箇所0件 |
| `REQUIREMENTS.md 3.4-3` | 「`{{単語}}` または `[単語]`」とあるが、`[単語]` は誤爆回避のため意図的に廃止済み |
| `REQUIREMENTS.md 3.4-2` | 単語カードを「28pt」と記載しているが、実装は32pt（Dynamic Type 対応済み） |

---

## 残作業の見積り

| 順 | 対応 | 規模 |
|---|---|---|
| 1 | **Xcodeをインストールし、アプリターゲットを作成**（[BLK-01](01-blockers.md#blk-01)） | 中（環境構築を含む） |
| 2 | [RFC-08](09-cleancode-refactoring-performance.md#rfc-08) 背景色ヘルパー6箇所を `Theme.swift` へ移動 | 小 |
| 3 | [UX-12](04-ui-ux-accessibility.md#ux-12) 「未分類」チップの追加（`FolderFilter` enum 化） | 小 |
| 4 | [NEW2-05](10-followup-review-2.md#new2-05) 非同期 `saveToDisk` の戻り値を削除 | 小 |
| 5 | [NEW2-07](10-followup-review-2.md#new2-07) `PasteButton` / `ShareLink` への置き換え | 小 |
| 6 | [CLN-04](09-cleancode-refactoring-performance.md#cln-04) `SRSParameters` の作成 | 小 |
| 7 | [PERF-06](09-cleancode-refactoring-performance.md#perf-06) / [NEW-17](08-followup-review.md#new-17) | 中 |

**2〜6はいずれも小規模です。** 実質的に残る大きな作業は BLK-01 だけと言えます。

---

## 総括

初回レビューから5ラウンドを通じて、**データ損失（保存競合）、SRSアルゴリズムの誤り、性能上の主要ボトルネック（統計画面1,042ms・トップ画面54ms・セッション終了2秒・判定ごと39ms）はすべて実測で解消**しました。学習ログの記録経路、永続化、テストのゲート機能も正しく機能しています。

残るのは **BLK-01（アプリターゲット）と、小規模な仕上げ8件** です。BLK-01 が完了すれば、初めて「iPhoneで動く暗記アプリ」として評価できる段階になります。**現時点ではまだ、iOSアプリとして一度も起動していないコードベースである**という点は、率直にお伝えしておきます。
