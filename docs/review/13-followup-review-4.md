# 13. 追補レビュー④（[12] 最終確認 後の対応検証）

- **レビュー日**: 2026-07-27（6回目）
- **対象**: [12. 最終確認](12-final-verification.md) で未対応・部分対応とした9件への対応後の全ソース（30ファイル）
- **検証方法**: クリーンビルド + `scripts/run_tests.sh` + **`project.pbxproj` の構造的検証（参照整合性・ファイル実在・登録漏れの機械チェック）** + 全ソースの該当箇所確認

---

## 総評

**ついに `kskAnki.xcodeproj` が作成されました。** 初回レビューから6ラウンド、最優先で指摘し続けた [BLK-01](01-blockers.md#blk-01) がようやく動き出しています。プロジェクトファイルは plist として妥当で、構造も正しく組まれています。

| 検査項目 | 結果 |
|---|---|
| `plutil -lint` | ✅ OK |
| アプリケーションターゲット | ✅ 1件（`com.apple.product-type.application`） |
| Bundle ID / Deployment Target | ✅ `com.ksk.kskAnki` / iOS 17.0 |
| `Info.plist` / `Assets.xcassets` の紐付け | ✅ 両方とも登録済み |
| 必須セクション（PBXProject / PBXNativeTarget / XCConfigurationList 等） | ✅ すべて存在 |
| `PBXBuildFile` → `PBXFileReference` の参照整合性 | ✅ 破綻0件 |
| Sources フェーズに列挙されたIDの定義 | ✅ 未定義0件 |
| 参照ファイルの実在 | ✅ 欠落0件 |

`@main` の扱いも正しく解決されています。`#if !SWIFT_PACKAGE` ガードにより、SwiftPM ビルド時（`SWIFT_PACKAGE` が定義される）は `@main` が除外されて検証ターゲットと衝突せず、Xcode アプリターゲット（`src/` を直接コンパイルするため `SWIFT_PACKAGE` は未定義）では `@main` が有効になります。

> **前回レビューの訂正**: [NEW2-08](10-followup-review-2.md#new2-08) で「`SWIFT_PACKAGE` は常に定義されるため `@main` は到達不能」と述べましたが、これはアプリターゲットがパッケージを依存として取り込む前提での指摘でした。実際の構成は `src/` を直接コンパイルする方式なので、**現在の実装が正しく、私の当初の指摘は当てはまりません**。

**ただし、このプロジェクトファイルでは iOS アプリがコンパイルできません。** ソースファイルが1つ登録漏れしています（→ [NEW4-01](#new4-01)）。

前回の残9件については、**5件が解消、1件が部分対応、3件が未対応**です。

---

## 対応状況

| 区分 | 件数 |
|---|---:|
| ✅ 解消 | 5 |
| ⚠️ 部分対応 | 2 |
| ❌ 未対応 | 3 |
| 🆕 新規指摘 | 3 |

SwiftPM のクリーンビルドは警告0・エラー0、検証スイート12件はすべて成功しています。

---

# 🔴 新規指摘

<a id="new4-01"></a>

## NEW4-01: `SRSParameters.swift` が Xcode プロジェクトに登録されておらず、アプリがコンパイルできない

**深刻度**: 🔴 Blocker
**該当**: `kskAnki.xcodeproj/project.pbxproj`, `src/Models/SRSParameters.swift`

[CLN-04](09-cleancode-refactoring-performance.md#cln-04) への対応として `src/Models/SRSParameters.swift` が新規作成されました。しかし **Xcode プロジェクトの Sources ビルドフェーズに登録されていません**。

`project.pbxproj` をディスク上のファイルと機械的に突合した結果です。

```
src配下の.swift:  27件
プロジェクト登録: 26件
プロジェクト未登録のソース: 1件 → ['src/Models/SRSParameters.swift']

$ grep -c "SRSParameters" kskAnki.xcodeproj/project.pbxproj
0
```

一方、`SRSParameters` は**6箇所から参照されています**。

```
src/Services/SpacedRepetition.swift:29  max(SRSParameters.minEaseFactor, ...)
src/Services/SpacedRepetition.swift:34  max(SRSParameters.minEaseFactor, ...)
src/Services/SpacedRepetition.swift:47  min(SRSParameters.defaultEaseFactor, ...)
src/Services/SpacedRepetition.swift:58  min(SRSParameters.maxIntervalDays, ...)
src/Services/DeckStore.swift:251        studyLogs.count > SRSParameters.maxStudyLogsCapacity
src/Services/DeckStore.swift:252        SRSParameters.maxStudyLogsCapacity
```

したがって Xcode でビルドすると **`Cannot find 'SRSParameters' in scope` が6件発生し、アプリターゲットのコンパイルが失敗します**。

`swift build` が通るのは、**SwiftPM が `src/` ディレクトリを丸ごとグロブする**のに対し、**Xcode プロジェクトはファイルを1つずつ明示列挙する**という仕組みの違いによるものです。今回の登録漏れは、この差異から生じています。

### 推奨対応

Xcode でプロジェクトを開き、`SRSParameters.swift` をターゲットに追加してください（Xcodeで一度でも開けば、通常はドラッグ&ドロップで解決します）。手で編集する場合は3箇所への追記が必要です。

```
1. PBXFileReference に SRSParameters.swift のエントリを追加
2. PBXBuildFile に上記を参照するエントリを追加
3. PBXSourcesBuildPhase の files = ( ... ) に追加
4. Models グループの children にも追加（Xcode上での表示のため）
```

**より重要なのは、この種の漏れを繰り返さない仕組みです。** 手書きの `project.pbxproj` はファイル追加のたびに同じ事故を起こします。以下のいずれかを推奨します。

- **XcodeGen / Tuist を導入**し、`project.yml` からプロジェクトを生成する（ディレクトリを glob できるため登録漏れが原理的に起きません）
- **アプリターゲットを SwiftPM パッケージ依存に変更**する。`kskAnkiCore` を依存に追加し、アプリターゲットには `@main` の1ファイルだけを置く構成にすれば、ソース追加時にプロジェクトを触る必要がなくなります（[NEW4-03](#new4-03) も同時に解決します）

---

<a id="new4-02"></a>

## NEW4-02: Xcode プロジェクトのビルドが一度も検証されていない

**深刻度**: 🟠 High
**該当**: 環境 / `.github/workflows/test.yml`

`project.pbxproj` は339行の手書きファイルで、**一度も Xcode で開かれておらず、ビルドも実行されていません**。

```
$ xcodebuild -list -project kskAnki.xcodeproj
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory
'/Library/Developer/CommandLineTools' is a command line tools instance
```

このMacにはフルXcodeが入っていないため、私も本レビューで**構造的な検証しかできませんでした**。[NEW4-01](#new4-01) の登録漏れは静的な突合で見つかりましたが、それ以外にも実際にビルドしないと分からない問題（コード署名設定、`Assets.xcassets` の中身、`UIApplicationSceneManifest` の整合、リンカ設定など）が残っている可能性があります。

**現時点で「iOSアプリがビルドできる」ことは、まだ誰も確認していません。**

### 推奨対応

1. **Xcodeをインストールし、`xcodebuild` で実際にビルドを通してください。** これが完了して初めて BLK-01 はクローズできます

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -project kskAnki.xcodeproj -scheme kskAnki \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
```

2. **CIにアプリビルドのジョブを追加してください。** 現在のCIは `./scripts/run_tests.sh`（SwiftPM側の検証）のみを実行しており、**アプリターゲットのビルドは対象外**です。今回のような登録漏れをCIで検出できません

```yaml
- name: Build iOS app
  run: |
    xcodebuild -project kskAnki.xcodeproj -scheme kskAnki \
      -destination 'platform=iOS Simulator,name=iPhone 15' \
      CODE_SIGNING_ALLOWED=NO build
```

---

<a id="new4-03"></a>

## NEW4-03: 同じソースが2つの異なる設定でコンパイルされる（Swift 5 / Swift 6 の不一致）

**深刻度**: 🟡 Medium
**該当**: `kskAnki.xcodeproj/project.pbxproj`, `Package.swift:1`

Xcode アプリターゲットは `src/` 配下の26ファイルを**直接コンパイル**します（SwiftPM パッケージへの依存ではありません）。つまり同じソースが2通りにビルドされます。

| ビルド経路 | Swift 言語モード | 並行性チェック |
|---|---|---|
| SwiftPM（`kskAnkiCore`） | **Swift 6**（`swift-tools-version: 6.0`） | 厳格 |
| Xcode アプリターゲット | **Swift 5**（`SWIFT_VERSION = 5.0`） | 緩い |

`@MainActor` / `actor PersistenceWriter` / `Sendable` といった記述は Swift 5 モードでもコンパイルできますが、**厳格な並行性チェックは適用されません**。結果として:

- パッケージ側のビルドで検出できるデータ競合が、アプリ側のビルドでは見逃されます
- 逆に、Swift 6 モード特有の挙動を前提にしたコードが、アプリ側で異なる意味を持つ可能性があります
- 検証スイート（`@testable import kskAnkiCore`）がテストしているのは**アプリが実際に使うコンパイル結果とは別物**です

### 推奨対応

言語モードを揃えてください。

```
SWIFT_VERSION = 6.0;
```

より根本的には [NEW4-01](#new4-01) で提案したとおり、**アプリターゲットを `kskAnkiCore` パッケージ依存に切り替える**のが最善です。ビルド設定が一元化され、ソース追加時のプロジェクト更新も不要になり、テストが実際のアプリコードを検証するようになります。

---

## ✅ 今回の対応で解消が確認できたもの（5件）

| ID | 内容 | 検証結果 |
|---|---|---|
| [UX-12](04-ui-ux-accessibility.md#ux-12) | 「未分類」を絞り込めない | `FolderFilter` enum（`.all` / `.unfiled` / `.folder(UUID)`）を導入し、チップも追加（`DeckListView.swift:10, 179, 225`）。指摘した設計どおりの実装です |
| [NEW-17](08-followup-review.md#new-17) | `studyLogs` が無制限に増加 | 10,000件を上限にトリミング（`DeckStore.swift:250-253`） |
| [NEW2-07](10-followup-review-2.md#new2-07) | クリップボードの直接読み取り | `PasteButton` を導入 |
| [NEW-13](08-followup-review.md#new-13) / [NEW-12](08-followup-review.md#new-12) / [UX-09](04-ui-ux-accessibility.md#ux-09) 等 | 前回確認済み | 引き続き解消状態を維持 |
| [BLK-01](01-blockers.md#blk-01) | Xcodeプロジェクト | **構造は作成された**（→ ただし [NEW4-01](#new4-01) [NEW4-02](#new4-02) が残るため未クローズ） |

---

## ⚠️ 部分対応（2件）

### 1. [CLN-04](09-cleancode-refactoring-performance.md#cln-04) — マジックナンバーの集約

`SRSParameters` は作成されましたが、**7個の定数のうち3個が未使用**で、対応するリテラルがコード中に残っています。

| 定数 | 利用箇所 | 対応するリテラルの残存 |
|---|---:|---|
| `minEaseFactor` | 2 | ✅ |
| `defaultEaseFactor` | 1 | ✅ |
| `maxIntervalDays` | 1 | ✅ |
| `maxStudyLogsCapacity` | 2 | ✅ |
| **`swipeThresholdWidth`** | **0** | ❌ `CardStudyView.swift:143` に `abs(w) > 90` |
| **`swipeRatioLimit`** | **0** | ❌ `CardStudyView.swift:143` に `abs(h) * 1.5` |
| **`csvImportLimit`** | **0** | ❌ `AddCardView.swift:216` に `prefix(2000)` |

定数を定義しただけで置き換えが済んでおらず、**「定義と実際の値が二重管理される」という、元の指摘より悪い状態**になっています。定数を変更しても挙動が変わりません。

```swift
// CardStudyView.swift:143 — 置き換えてください
if abs(w) > abs(h) * SRSParameters.swipeRatioLimit && abs(w) > SRSParameters.swipeThresholdWidth {
```

なお `csvImportLimit = 2000` という名前は、実際の用途（1行あたりの最大文字数）と一致していません。以前あった「取り込み最大500行」の制限とも混同しやすいため、`csvMaxLineLength` のような名前に変えてください。

### 2. [BLK-01](01-blockers.md#blk-01) — iOSアプリターゲット

上記 [NEW4-01](#new4-01) / [NEW4-02](#new4-02) のとおり、**プロジェクトは作成されたがビルドは通りません**。

---

## ❌ 未対応（3件）

| ID | 深刻度 | 確認結果 |
|---|---|---|
| [RFC-08](09-cleancode-refactoring-performance.md#rfc-08) | 🟡 | `Theme.swift` は存在しますが、背景色ヘルパーは**3ファイル6箇所に残ったまま**です（`DeckListView` / `FlashcardView` / `StudyStatsView`）。移すだけの作業です |
| [PERF-06](09-cleancode-refactoring-performance.md#perf-06) | 🟡 | `grep -c "lazy" src/Models/StudyFilter.swift` → **0**。件数取得のための配列コピー（実測 6.65 ms）は未改善 |
| [NEW2-05](10-followup-review-2.md#new2-05) | 🟡 | 非同期 `saveToDisk()` は依然として無条件で `return true`。シグネチャが実態と一致していません |

[QA-07](06-code-quality-and-testing.md#qa-07)（i18n）も未対応ですが、日本語専用として進めるなら優先度は低い項目です。

---

## 補足: `NEW-17` のトリミングに伴う副作用

ログ上限の実装は妥当ですが、`studyLogs.removeFirst()` は**最も古いログから削除**します。ストリークは `studyDaysCache` から算出されるため実行中は影響しませんが、**アプリ再起動時に `recalculateMetrics()` がトリミング後のログから再構築するため、上限に達した後は過去のストリーク履歴が失われます**。

1日20枚のペースなら10,000件は約500日ぶんなので当面は問題ありません。ただし [NEW-17](08-followup-review.md#new-17) で提案した「古いログを日次集計に畳む」方式にすれば、履歴を保ったまま容量を抑えられます。将来の改善候補として記録しておきます。

---

## 次のアクション

| 順 | 対応 | 規模 |
|---|---|---|
| 1 | [NEW4-01](#new4-01) `SRSParameters.swift` をXcodeプロジェクトに追加 | 小（ただし**これが無いとアプリが1行もビルドできません**） |
| 2 | [NEW4-02](#new4-02) Xcodeをインストールし、実際に `xcodebuild` でビルドを通す | 中（BLK-01 のクローズ条件） |
| 3 | CIにアプリビルドのジョブを追加 | 小 |
| 4 | [CLN-04](09-cleancode-refactoring-performance.md#cln-04) 未使用の3定数をリテラルと置き換え | 小 |
| 5 | [RFC-08](09-cleancode-refactoring-performance.md#rfc-08) 背景色ヘルパー6箇所を `Theme.swift` へ移動 | 小 |
| 6 | [NEW2-05](10-followup-review-2.md#new2-05) 非同期版の戻り値を削除 | 小 |
| 7 | [NEW4-03](#new4-03) `SWIFT_VERSION = 6.0` に統一、またはパッケージ依存へ移行 | 小〜中 |
| 8 | [PERF-06](09-cleancode-refactoring-performance.md#perf-06) `lazy` の導入 | 小 |

---

## 総括

**BLK-01 は6ラウンド目にして大きく前進しました。** プロジェクトファイルの構造自体は正しく作られており、`@main` のガード方法も適切です。残るのは**ソース1ファイルの登録漏れ**と、**実ビルドによる検証**の2点だけです。

一方で、今回の登録漏れは示唆的です。**手書きの `project.pbxproj` は、ソースを追加するたびに同じ事故を起こします。** 今回は `SRSParameters.swift` でしたが、次に新しいファイルを追加したときも同様のことが起きます。XcodeGen の導入か、アプリターゲットをパッケージ依存にする構成変更を、BLK-01 のクローズと合わせて検討することを強く推奨します。

また、**CIがアプリターゲットのビルドを検証していない**点も、この問題を見逃した一因です。SwiftPM 側の検証は正しく機能していますが（12件すべて成功）、アプリが壊れていても緑のままです。CIにビルドジョブを1つ足すだけで、この種の問題は自動的に検出できるようになります。
