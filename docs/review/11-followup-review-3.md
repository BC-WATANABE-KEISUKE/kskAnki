# 11. 追補レビュー③（[10] 対応後の再検証）

- **レビュー日**: 2026-07-26（4回目）
- **対象**: [10. 追補レビュー②](10-followup-review-2.md)（新規9件）および過去指摘への対応後の全ソース（29ファイル）
- **検証方法**: 全ソース精読 + クリーンビルド + `scripts/run_tests.sh` + **ベンチマーク再計測** + **競合状態の再現テスト再実行** + **サンプルデータ復活の再現テスト**

---

## 総評

**前回の新規指摘9件のうち8件が解消しました。** 特に重要な2つのブロッカーが実測で確認できるレベルで直っています。

- **[NEW2-02](10-followup-review-2.md#new2-02)（非同期保存の競合によるデータ損失）が完治しました。** `PersistenceWriter` アクターの導入により書き込みが直列化され、**同じ再現テストを6回実行して6回とも成功**しました（前回は4回中2回で失敗、最悪7回分が消失）
- **[NEW2-03](10-followup-review-2.md#new2-03)（判定1回あたり39.3ms）が `recordStudy()` の O(1) 差分更新化で解消しました。** 実測 **39.30ms → 0.059 ms（約666倍）**。`studyDaysCache` を保持して差分だけ見る、という指摘どおりの実装です
- **[NEW2-09](10-followup-review-2.md#new2-09)（要件3.1の機能消失）が完全に復旧**しました。ソート・ページネーション・アーカイブ切替・コンテキストメニューがすべて戻り、加えて **[UX-11](04-ui-ux-accessibility.md#ux-11)（削除確認ダイアログ）と [UX-13](04-ui-ux-accessibility.md#ux-13)（ページ番号のクランプ）も同時に修正**されています
- **[NEW2-01](10-followup-review-2.md#new2-01)（CI不全）**、**[NEW2-04](10-followup-review-2.md#new2-04)（`.gitignore`）**、**[NEW2-06](10-followup-review-2.md#new2-06)（復元後のメトリクス）**、**[NEW2-08](10-followup-review-2.md#new2-08)（到達不能な `@main`）** もすべて対応済みです

さらに、**長く未着手だった `AudioService` にようやく手が入りました**。`.ambient` カテゴリによるマナーモード尊重と `setActive(false)` の解放（[SEC-03](05-security-and-privacy.md#sec-03)）、`NLLanguageRecognizer` による言語判定（[QA-05](06-code-quality-and-testing.md#qa-05)）が実装されています。穴埋めパーサも書き直され、**[NEW-04](08-followup-review.md#new-04)（複数空欄で誤った頭文字）と [UX-15](04-ui-ux-accessibility.md#ux-15)（`[...]` の誤爆）が同時に解消**しました。

**一方で、新たに3件の問題があります。**

1. **[ARC-03](02-architecture-and-data.md#arc-03)（サンプルデータの復活）が再発しました。** `DeckStore.init()` の判定が `if !loadFromDisk()` から `if courses.isEmpty` に変わったため、**全コースを削除して再起動すると、削除したはずのサンプルコースが復活します**（再現済み）
2. **`updateCourse()` が 35.75ms** かかります。メトリクスは `studyLogs` にしか依存しないのに、コース更新のたびに全ログを再走査する `recalculateMetrics()` を呼んでいます。**完全に不要な処理**です
3. **[PERF-05](09-cleancode-refactoring-performance.md#perf-05)（画像のフルサイズデコード）は API だけ追加されて配線されていません。** `loadDownsampledImage` は実装されましたが、`FlashcardView` は従来どおり `loadImage`（フルサイズ）を `body` から呼んでいます

**[BLK-01](01-blockers.md#blk-01) は前進しましたが、まだ完了していません。** `Info.plist` と `Assets.xcassets` が作成され、`.gitignore` も修正され、`Package.swift` の `exclude` 設定も正しく入りました。しかし **`.xcodeproj` が存在しないため、依然としてiOSアプリをビルド・起動できません**。

---

## 対応状況サマリー

| 区分 | 件数 |
|---|---:|
| ✅ 今回で解消 | **16** |
| ⚠️ 部分対応 | 4 |
| ❌ 未対応 | 12 |
| 🆕 新規指摘 | **3** |

---

## 📊 ベンチマーク再計測

同一条件（**カード5,000枚 / 学習ログ14,600件**、release ビルド）。

| 計測対象 | 前回 | 今回 | 判定 |
|---|---:|---:|---|
| **`store.recordStudy()`（判定ごと）** | 39.30 ms | **0.059 ms** | ✅ 約666倍高速化 |
| `store.saveToDisk()`（非同期） | 0.003 ms | 0.001 ms | ✅ 直列化しても速度維持 |
| `store.saveToDiskSync()` | 93.52 ms | 87.02 ms | ─ 同期版の実処理コスト |
| **`store.updateCourse()`** | ─ | **35.75 ms** | 🆕 [NEW3-02](#new3-02) 不要な全走査 |
| `store.recalculateMetrics()` | 36.95 ms | 35.89 ms | ─ 起動時のみなら許容 |

### 競合状態の再現テスト（再実行）

前回データ損失を再現したテストを、同じ条件で6回実行しました。

```
=== NEW2-02 競合の再現テスト（前回は4回中2回で失敗） ===
  ✅ STATE-20 一致
  ✅ STATE-20 一致
  ✅ STATE-20 一致
  ✅ STATE-20 一致
  ✅ STATE-20 一致
  ✅ STATE-20 一致
```

**6回中6回成功。`PersistenceWriter` アクターによる直列化が正しく機能しています。**

---

# 🔴 新規指摘

<a id="new3-01"></a>

## NEW3-01: 【再発】全コースを削除して再起動すると、サンプルデータが復活する

**深刻度**: 🔴 Blocker（ユーザー操作の取り消し）
**該当**: `src/Services/DeckStore.swift:69-79`

`DeckStore.init()` の初期化判定が変更されました。

```swift
public init() {
    ...
    loadFromDisk()
    if courses.isEmpty {          // ← 「保存ファイルが無い」ではなく「コースが空」で判定
        loadSampleData()
    }
    recalculateMetrics()
}
```

以前は `if !loadFromDisk()` でした。これは「**保存ファイルが存在しない＝初回起動**」を正しく判定していました。現在の `courses.isEmpty` は「**コースが0件**」を判定するため、**ユーザーが意図的に全コースを削除した状態と、初回起動が区別できません**。

### 再現実験

```
① 初回起動 → サンプル投入
   コース数: 2
② ユーザーが全コースを削除
   コース数: 0
③ アプリ再起動
   コース数: 2
   ❌ サンプルデータ 2 件が復活（ARC-03 の再発）:
      ["Google Cloud Associate Cloud Engineer (ACE) 対策", "ITエンジニアのための実践英単語"]
```

これは初回レビューの [ARC-03](02-architecture-and-data.md#arc-03) で指摘し、2回目のレビューで**解消を確認していた項目の再発**です。ユーザーから見ると「削除したコースが勝手に戻る」「消せないコースがある」という挙動になります。

### 推奨対応

「初回起動か」をファイルの有無で判定してください。

```swift
public init() {
    ...
    let didLoad = loadFromDisk()
    if !didLoad {
        loadSampleData()          // 保存ファイルが無いときだけシードする
        saveToDiskSync()
    }
    recalculateMetrics()
}
```

より堅牢にするなら、`UserDefaults` に `hasSeededInitialData` フラグを持たせてください。保存ファイルが破損して `loadFromDisk()` が false を返した場合でも、サンプルデータで上書きせずに済みます。

**この再発は、[NEW-14](08-followup-review.md#new-14)（保存先が注入できずテストを書けない）が未対応であることの直接的な帰結です。** `DeckStore(storageURL:)` で一時ディレクトリを指定できれば、「全削除 → 再生成 → 空であること」を検証するテストが数行で書けます。

---

<a id="new3-02"></a>

## NEW3-02: `updateCourse()` が不要な全ログ再走査で 35.75ms かかる

**深刻度**: 🟠 High
**該当**: `src/Services/DeckStore.swift:193-205, 214-236`

[NEW2-03](10-followup-review-2.md#new2-03) の対応で `recordStudy()` は O(1) 化されましたが、**メトリクスと無関係なAPIから `recalculateMetrics()`（全走査 35.89ms）が呼ばれています**。

```swift
public func updateCourse(_ updatedCourse: Course) {
    if let idx = courses.firstIndex(where: { $0.id == updatedCourse.id }) {
        courses[idx] = updatedCourse
        recalculateMetrics()          // ← 35.89 ms。studyLogs は変わっていない
        saveToDisk()
    }
}

public func deleteCourse(_ courseId: UUID) {
    courses.removeAll { $0.id == courseId }
    recalculateMetrics()              // ← 同上
    saveToDisk()
}

public func updateCardsInDeckBulk(_ updatedCards: [AnkiCard], inDeckId deckId: UUID) {
    ...
    recalculateMetrics()              // ← 同上
    saveToDisk()
}
```

`recalculateMetrics()` が読むのは `studyLogs` だけです（`DeckStore.swift:82-89`）。これらのAPIは `courses` しか変更しないため、**再計算はまったく不要**です。

**実測: `store.updateCourse()` = 35.75 ms。**

`updateCourse` は `CourseDetailView` の `onSaveCourse` から呼ばれるため、**カードの追加・編集・削除・お気に入り切替のたびに35.75msのひっかかり**が生じます。[PERF-02](09-cleancode-refactoring-performance.md#perf-02) で消したはずの全走査が、別の経路で戻ってきた形です。

### 推奨対応

該当3箇所から `recalculateMetrics()` を削除してください。メトリクスの更新が必要なのは以下の3つの場面だけです。

| 場面 | 対応 |
|---|---|
| 起動・ディスクからのロード | `init` / `loadFromDisk` で全走査（現状どおり） |
| 学習の記録 | `recordStudy` の O(1) 差分更新（現状どおり） |
| バックアップからの復元 | `BackupService.importBackupJSON` で全走査（現状どおり） |

`studyLogs` を `private(set)` にして変更経路を上記に限定すれば、「どこで再計算が必要か」がコンパイラレベルで明確になります。

---

<a id="new3-03"></a>

## NEW3-03: ダウンサンプリングAPIが実装されたが、どこからも使われていない

**深刻度**: 🟠 High
**該当**: `src/Services/ImageStore.swift:36-58`, `src/Views/FlashcardView.swift:393`

[PERF-05](09-cleancode-refactoring-performance.md#perf-05) への対応として `loadDownsampledImage(path:pointSize:scale:)` が追加されました。`CGImageSourceCreateThumbnailAtIndex` を使った実装自体は正しく、推奨した内容そのものです。

**しかし呼び出し元がありません。**

```
$ grep -rn "loadDownsampledImage" src/
src/Services/ImageStore.swift:37:    public static func loadDownsampledImage(...)   ← 定義のみ

$ grep -n "ImageStore.loadImage" src/Views/FlashcardView.swift
393:            if let uiImage = ImageStore.loadImage(path: urlString) {   ← フルサイズ版のまま
```

`FlashcardView` は従来どおり `loadImage`（`UIImage(contentsOfFile:)`）を **`body` の中から**呼んでいます。したがって [PERF-05](09-cleancode-refactoring-performance.md#perf-05) で指摘した2つの問題は**実際には何も変わっていません**。

- 12MPの写真1枚で約48MBのビットマップをメモリ展開し、それを **140×100pt** で表示している
- `body` から呼ぶためキャッシュが効かず、**レンダリングのたびにディスクI/O + デコード**が走る

また、**保存時のダウンサンプリングも未実装**です。`saveImage` は `PhotosPicker` から受け取ったオリジナルデータをそのまま書き込み、拡張子だけ `.jpg` を付けています（iOSの写真は既定でHEICのため、中身と拡張子が食い違ったままです）。

### 推奨対応

1. 呼び出し側を差し替える

```swift
// FlashcardView.swift:393
if let uiImage = ImageStore.loadDownsampledImage(
        path: urlString,
        pointSize: CGSize(width: 140, height: 100)) {
```

2. `body` からの同期デコードをやめ、`.task` で非同期に読み込んで `@State` に保持する。加えて `NSCache<NSString, UIImage>` を `ImageStore` に持たせる（現状キャッシュは未実装）
3. `saveImage` でも保存時にダウンサンプリング＋JPEG再圧縮を行い、拡張子と中身を一致させる

---

# ✅ 今回の対応で解消が確認できたもの

| ID | 内容 | 検証結果 |
|---|---|---|
| [NEW2-01](10-followup-review-2.md#new2-01) | CIが `swift test` で常時レッド | ワークフローが `./scripts/run_tests.sh` に変更され、`chmod +x` ステップも追加済み |
| [NEW2-02](10-followup-review-2.md#new2-02) | 非同期保存の競合でデータ損失 | `PersistenceWriter` アクターで直列化。**再現テスト6/6成功** |
| [NEW2-03](10-followup-review-2.md#new2-03) | 判定ごとに39.3ms | `studyDaysCache` による O(1) 差分更新。**実測 0.059 ms** |
| [NEW2-04](10-followup-review-2.md#new2-04) | `.gitignore` が `*.xcodeproj` を除外 | `xcuserdata/` のみに変更。`.build/` の混入も0件 |
| [NEW2-05](10-followup-review-2.md#new2-05) | `saveToDisk` が常に `true` | `saveToDiskSync()` が実際の成否を返すよう分離（→ 部分対応、後述） |
| [NEW2-06](10-followup-review-2.md#new2-06) | 復元後にメトリクスが古いまま | `BackupService.swift:38` で `recalculateMetrics()` を呼ぶよう修正 |
| [NEW2-07](10-followup-review-2.md#new2-07) | 無言でクリップボードを読む | シートを開いた瞬間の自動読み取りを廃止し、明示的なボタン操作に変更（→ 部分対応、後述） |
| [NEW2-08](10-followup-review-2.md#new2-08) | 到達不能な `@main` | `#if !SWIFT_PACKAGE` ブロックを削除。`kskAnkiAppView` のみ残存 |
| [NEW2-09](10-followup-review-2.md#new2-09) | 要件3.1の機能4つが消失 | ソート・ページャ・アーカイブ切替・コンテキストメニューをすべて復旧 |
| [NEW-04](08-followup-review.md#new-04) | 複数空欄で誤った頭文字 | `maskedCloze` が各マッチを個別走査し、`m.range(at: 1)` で正しい頭文字を付与 |
| [UX-15](04-ui-ux-accessibility.md#ux-15) | 穴埋めの `[...]` 誤爆 | 正規表現が `\{\{(.+?)\}\}` のみになり、`array[0]` が誤マスクされなくなった |
| [NEW-08](08-followup-review.md#new-08) | 表面の朗読ボタン消失 | 表面ヘッダー（`FlashcardView.swift:59`）に復活 |
| [NEW-09](08-followup-review.md#new-09) | カテゴリーバッジ消失 | `CourseContentView.swift:130` に復活 |
| [UX-11](04-ui-ux-accessibility.md#ux-11) | コース削除に確認がない | `alert("コースの削除確認")` を追加（`DeckListView.swift:90`） |
| [UX-13](04-ui-ux-accessibility.md#ux-13) | ページ番号がクランプされない | `let validPage = min(max(1, currentPage), totalPages)` を追加 |
| [SEC-03](05-security-and-privacy.md#sec-03) | `AVAudioSession` を解放しない・消音無視 | `.ambient` + `.spokenAudio` に変更し、`didFinish` で `setActive(false)` |
| [QA-05](06-code-quality-and-testing.md#qa-05) | 言語自動判定が粗い | `NLLanguageRecognizer` を導入。6言語に対応 |

> **`AudioService.swift` は初回レビューから3回連続で未着手でしたが、今回ようやく修正されました。** SEC-03 と QA-05 が同時に解消しています。

---

## ⚠️ 部分対応

| ID | 残っている点 |
|---|---|
| [BLK-01](01-blockers.md#blk-01) | `Info.plist` / `Assets.xcassets` / `.gitignore` / `Package.swift` の `exclude` は整備済み。**しかし `.xcodeproj` が無く、iOSアプリはビルドできません**（→ [下記](#blk-01-status)） |
| [NEW2-05](10-followup-review-2.md#new2-05) | `saveToDiskSync()` は実際の成否を返すようになりましたが、`saveToDisk(sync: false)` は依然として**無条件で `true` を返します**（`DeckStore.swift:152`）。非同期パスは `Bool` を返さないシグネチャにするのが素直です |
| [NEW2-07](10-followup-review-2.md#new2-07) | シートを開いた瞬間の自動読み取りは解消しました。ただし依然として `UIPasteboard.general.string` を直接読むため、iOS 16+ のペースト許可ダイアログが出ます。`PasteButton` に置き換えてください。書き出し側（`SettingsView.swift:90`）も全データをクリップボードへコピーしたままです |
| [PERF-05](09-cleancode-refactoring-performance.md#perf-05) | API のみ追加。配線されていません（→ [NEW3-03](#new3-03)） |

<a id="blk-01-status"></a>

### BLK-01 の現状

| 項目 | 状態 |
|---|---|
| `src/App/Info.plist` | ✅ 作成済み。Bundle ID・画面向き・用途説明（写真/カメラ/音声認識）を設定 |
| `src/App/Assets.xcassets` | ✅ 作成済み |
| `.gitignore` | ✅ `*.xcodeproj` の除外を解除 |
| `Package.swift` | ✅ `exclude: ["App/Info.plist", "App/Assets.xcassets"]` でリソース警告を回避 |
| `kskAnkiAppView` | ✅ 公開ビューとして提供済み |
| **`.xcodeproj` / アプリターゲット** | ❌ **未作成** |

**部品は揃いましたが、それらを束ねるアプリターゲットがまだありません。** 現状では `Info.plist` も `Assets.xcassets` も、どのビルドからも参照されていないファイルです。

このMacにはフルXcodeがインストールされていないため（`xcrun --show-sdk-path` が Command Line Tools を指しています）、**Xcodeのインストールが次の一手の前提**になります。これは [NEW2-01](10-followup-review-2.md#new2-01) で述べた「`canImport(XCTest)` が false になる」問題の原因でもあります。

---

## ❌ 未対応のまま残っている指摘

| ID | 深刻度 | 内容 |
|---|---|---|
| [NEW-12](08-followup-review.md#new-12) | 🟡 | カード切替時に `isEditingNotes` が解除されない（`FlashcardView.swift:256-259`） |
| [NEW-13](08-followup-review.md#new-13) | 🟡 | `backText` が空でも解答ブロックを表示（要件3.5の動的非表示に違反） |
| [NEW-14](08-followup-review.md#new-14) | 🟡 | 保存先が注入できず、テストが実 `~/Documents` を汚染。**[NEW3-01](#new3-01) の再発を許した根本原因** |
| [NEW-17](08-followup-review.md#new-17) | 🟡 | `studyLogs` が無制限に増加し、毎回の保存で全件シリアライズ |
| [UX-09](04-ui-ux-accessibility.md#ux-09) | 🔵 | 進捗バーが1枚目で100%（`ProgressView(value: Double(current))`） |
| [UX-12](04-ui-ux-accessibility.md#ux-12) | 🟡 | 「未分類」フォルダを絞り込めない |
| [UX-14](04-ui-ux-accessibility.md#ux-14) | 🟡 | `themeColorHex` が描画に使われず、コースカードは `Color.blue` 固定 |
| [SEC-02](05-security-and-privacy.md#sec-02) | 🟡 | `playAudio` がURLスキームを検証しない（`AudioService.swift:57`） |
| [PERF-06](09-cleancode-refactoring-performance.md#perf-06) | 🟡 | 件数取得のために配列コピーを生成（`lazy` 未導入） |
| [CLN-04](09-cleancode-refactoring-performance.md#cln-04) | 🟡 | SRSパラメータ等のマジックナンバーが散在（`SRSParameters` 未作成） |
| [RFC-08](09-cleancode-refactoring-performance.md#rfc-08) | 🟡 | 背景色ヘルパーが5箇所に重複（`Theme.swift` 未作成） |
| [QA-07](06-code-quality-and-testing.md#qa-07) | 🔵 | i18n未対応 |

### 補足: 要件書の更新が必要な箇所

[UX-15](04-ui-ux-accessibility.md#ux-15) への対応で `[単語]` 記法のサポートが落とされました。**これは私の推奨に沿った正しい判断**ですが、`REQUIREMENTS.md 3.4-3` は現在も「`{{単語}}` **または** `[単語]` 箇所を動的認識」と記載しています。実装が仕様の正になったので、**要件書側を `{{単語}}` のみに更新**してください。

同様に、`REQUIREMENTS.md 1` の技術スタックには「Combine」が挙がっていますが、現在も使用箇所は0件です。

---

## 次のアクション（優先順）

| 順 | 対応 | 理由 |
|---|---|---|
| 1 | [NEW3-01](#new3-01) `init()` の初期化判定を `if !loadFromDisk()` に戻す | **削除したデータが復活します。** 1行の修正 |
| 2 | [NEW-14](08-followup-review.md#new-14) `DeckStore(storageURL:)` で保存先を注入可能にする | [NEW3-01](#new3-01) のような再発を検出するテストが書けるようになります |
| 3 | [NEW3-02](#new3-02) 不要な `recalculateMetrics()` を3箇所から削除 | カード編集ごとの35.75msが消えます。削除するだけ |
| 4 | Xcodeをインストールし、[BLK-01](01-blockers.md#blk-01) を完了させる | 部品は揃いました。あと一歩でアプリが起動します |
| 5 | [NEW3-03](#new3-03) `loadDownsampledImage` を配線 + キャッシュ追加 | APIは既にあります。呼び出し側の差し替えが主 |
| 6 | [NEW-12](08-followup-review.md#new-12) / [NEW-13](08-followup-review.md#new-13) / [UX-09](04-ui-ux-accessibility.md#ux-09) | いずれも1〜3行の修正 |

**このラウンドは明確に良い進捗です。** 実測で確認できたデータ損失と性能劣化の両方が解消し、3回連続で放置されていた `AudioService` にも手が入りました。

残る課題は、**BLK-01（Xcode環境）** と **テストの密閉性（NEW-14）** の2点に集約されています。特に後者は、[NEW3-01](#new3-01) のような「一度直した項目の再発」を機械的に防ぐために重要です。現在の検証スイート12件はすべて実行されており（`run_tests.sh` は失敗も正しく検出します）、あとは保存先を注入できるようにするだけで、永続化まわりの回帰テストを書ける状態になります。
