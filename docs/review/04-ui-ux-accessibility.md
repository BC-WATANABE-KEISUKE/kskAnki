# 04. UI/UX & アクセシビリティ

対象: `src/Views/` 配下10ファイル

---

<a id="ux-01"></a>

## UX-01: 同一軸の `ScrollView` が二重にネストしている

**深刻度**: 🟡 Medium
**該当**: `src/Views/CardStudyView.swift:41`, `src/Views/FlashcardView.swift:29`

```swift
// CardStudyView.swift:41
ScrollView {
    FlashcardView(card: currentCard, isRevealed: $isRevealed) { ... }
}

// FlashcardView.swift:29 — 中身もまた ScrollView
ScrollView(.vertical, showsIndicators: true) { ... }
.frame(maxHeight: 520)
```

縦方向の `ScrollView` の中に縦方向の `ScrollView` を入れる構成は iOS では推奨されません。内側がスクロール端に達しても外側へスクロールが引き継がれず、指を離して再度スワイプし直す必要があります。ユーザーには「途中で引っかかる」「スクロールが効かない箇所がある」という体感になります。

`REQUIREMENTS.md 3.3-①` は「長文テキストや複数画像がある場合、画面枠を超えてスムーズに縦スクロール可能」を求めており、この構成では満たせません。

### 推奨対応

`ScrollView` は**どちらか一方に統一**してください。カード全体が1つのスクロール領域になるほうが自然です。

```swift
// CardStudyView 側の ScrollView を残し、FlashcardView は素の VStack にする
// （FlashcardView.swift:29 の ScrollView と :245 の .frame(maxHeight: 520) を削除）
```

---

<a id="ux-02"></a>

## UX-02: スワイプ判定用の `DragGesture` がスクロールと競合する（特に「上スワイプ = △」）

**深刻度**: 🟠 High
**該当**: `src/Views/CardStudyView.swift:49-53, 122-146`

```swift
ScrollView { ... }
    .offset(x: dragOffset.width, y: dragOffset.height)
    .gesture(isRevealed ? swipeGesture : nil)   // DragGesture
```

`ScrollView` に `DragGesture` を `.gesture()` で付けると、**ジェスチャがスクロールを奪います**。加えて判定ロジックが軸を区別していません。

```swift
if w > 100        { handleRating(.correct) }     // 右
else if w < -100  { handleRating(.incorrect) }   // 左
else if h < -100  { handleRating(.doubtful) }    // 上
```

問題は2点です。

1. **「上スワイプ = △」はコンテンツを下へスクロールする操作と物理的に同一**です。長い解説を読もうとして100pt以上スクロールすると、意図せず△が記録されて次のカードへ進みます。要件3.3-①（スクロール可能）と要件3.3-①（上スワイプで△）が、そのままでは両立しません。
2. 横スワイプ判定に縦方向の許容量がないため、斜めに動かすと横判定が優先されます（`w > 100` を先に評価するため、右下方向に大きく引いても◯になります）。

`.scratch/card-interaction-and-rating/spec.md` が謳う「1枚1秒のテンポ」を実現するには、誤爆しないジェスチャ設計が前提です。

### 推奨対応

- △ の割り当てを**上スワイプから外す**（例: ダブルタップ、または画面下部の△ボタンのみ）ことを最も強く推奨します。スクロールと競合しない軸は横方向だけです
- 横スワイプは軸のロックと角度判定を入れる

```swift
.onEnded { g in
    let w = g.translation.width, h = g.translation.height
    guard abs(w) > abs(h) * 1.5, abs(w) > 100 else { return }   // 横方向が支配的な時だけ判定
    handleRating(w > 0 ? .correct : .incorrect)
}
```

- スクロールとの共存には `.simultaneousGesture` または `ScrollView` の外側のカードコンテナにジェスチャを付ける構成を検討してください
- 判定確定時に `.sensoryFeedback` で触覚を返すと誤爆に気づきやすくなります（ARC-05のHaptics未実装とセットで対応可能）

---

<a id="ux-03"></a>

## UX-03: PhotosPicker が完全な空実装 — 写真を選んでも何も起きない

**深刻度**: 🟠 High
**該当**: `src/Views/AddCardView.swift:35-36, 115, 154`, `src/Views/EditCardView.swift:34-35, 103, 142`

```swift
@State private var selectedFrontPhotoItems: [PhotosPickerItem] = []
...
PhotosPicker(selection: $selectedFrontPhotoItems, maxSelectionCount: 5, matching: .images) { ... }
```

`selectedFrontPhotoItems` / `selectedBackPhotoItems` は **宣言と `PhotosPicker` へのバインドのみ**で、値を観測する `.onChange` も、データを取り出す `loadTransferable` も存在しません（全文検索で `loadTransferable` のヒット0件）。

ユーザーの体験:
1. 「フォトライブラリから画像を選択」をタップ
2. ピッカーが開き、写真を選んで完了
3. **何も起きない**。「登録予定の表面画像」リストは空のまま
4. 保存しても画像は1枚も付かない

`REQUIREMENTS.md 3.6`「`PhotosPicker` により、iPhoneのフォトライブラリから直接画像を選択して登録可能（削除機能付き）」は未実装です。UIだけが先に置かれており、機能があるように見える分たちが悪い状態です。

### 推奨対応

選択を検知してデータを取り出し、**アプリコンテナに永続保存**してから相対パスを配列に追加します（`PhotosPickerItem` の識別子はアプリ再起動後に解決できないため、ファイルとして保存する必要があります）。

```swift
.onChange(of: selectedFrontPhotoItems) { _, items in
    Task {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            if let fileName = try? ImageStore.save(data) {   // Documents配下に保存し、ファイル名を返す
                frontImageURLs.append(fileName)
            }
        }
        selectedFrontPhotoItems = []
    }
}
```

同じ処理が4箇所（Add/Edit × 表/裏）に必要になるので、`ImagePickerSection` のような共通Viewへ切り出すことを推奨します。

---

<a id="ux-04"></a>

## UX-04: ローカル画像パスが表示できない — `http` で始まるURLしかレンダリングしない

**深刻度**: 🟠 High
**該当**: `src/Views/FlashcardView.swift:453`, `src/Views/ImageDetailView.swift:23`

```swift
if let url = URL(string: urlString), urlString.hasPrefix("http") {
    AsyncImage(url: url) { ... }
} else {
    Image(systemName: "photo.fill")     // ← プレースホルダーのアイコンのみ
}
```

画像の描画経路が **リモートHTTP画像専用** になっています。ローカルファイルパス（`file://` やDocuments配下の相対パス）は問答無用でグレーのプレースホルダーになります。

UX-03を修正してPhotosPickerを実装しても、**保存した画像は表示されません**。両方をセットで直す必要があります。

拡大表示 (`ImageDetailView.swift:23`) も同じ条件分岐なので、ローカル画像はピンチズームも効きません（要件3.6）。

加えて、リモート画像への依存はオフライン学習と相性が悪い点も指摘しておきます。`docs/specs/tech-stack-proposal.md` は「オフラインでもサクサク動くこと」を要件の柱に挙げていますが、`AsyncImage` はディスクキャッシュを持たないため、電波のない電車内では画像が全滅します。

### 推奨対応

ローカル/リモートを分岐し、ローカルを第一級に扱ってください。

```swift
@ViewBuilder
private func cardImage(_ path: String) -> some View {
    if path.hasPrefix("http"), let url = URL(string: path) {
        AsyncImage(url: url) { ... }
    } else if let uiImage = ImageStore.load(path) {     // Documents配下から読む
        Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fit)
    } else {
        Image(systemName: "photo.fill") ...
    }
}
```

将来的にはリモート画像も取り込み時にローカルへコピーする方針を推奨します。

---

<a id="ux-05"></a>

## UX-05: アクセシビリティ対応が皆無 — VoiceOverで判定ボタンが機能しない

**深刻度**: 🟠 High
**該当**: `src/Views/` 全体（`accessibility` の全文検索でヒット0件）

アプリ全体でアクセシビリティ修飾子が **1つも使われていません**。特に影響が大きい箇所:

| 箇所 | 問題 |
|---|---|
| `CardStudyView.swift:246-269` 判定ボタン | ラベルが記号 `✕` `△` `◯` ＋ 日本語。VoiceOverは「バツ 不正解」「三角 惜しい」のように記号名を読み上げるか、フォントによっては無音になります |
| `FlashcardView.swift:449-497` 画像 | `accessibilityLabel` がなく、VoiceOverでは「イメージ」としか読まれません |
| `FlashcardView.swift:377-386` 穴埋めマスク | `[ ❓ 隠し (タップでヒント) ]` がそのまま読み上げられ、文脈が壊れます |
| `DeckListView.swift:344-369` ページ送り | `chevron.left/right` のみでラベルなし。「ボタン」としか読まれません |
| スワイプ判定 | 代替のボタンが存在するので致命的ではありませんが、`accessibilityAction` の提供が望ましいです |

暗記アプリは視覚障害のある学習者にも需要が大きい領域です。App Store のアクセシビリティ関連の評価にも直結します。

### 推奨対応

```swift
// 判定ボタン
Button { handleRating(rating) } label: { ... }
    .accessibilityLabel(rating.label)                    // 既に "不正解 (✕)" 等が定義済み (AnkiCard.swift:42)
    .accessibilityHint("このカードの理解度を記録して次へ進みます")

// 画像
.accessibilityLabel("カードの画像 \(index + 1) / \(urls.count)")
.accessibilityAddTraits(.isButton)

// ページ送り
.accessibilityLabel("前のページ")
```

`Rating.label` は既に適切な文字列を持っているので、繋ぎ込むだけで大半が解決します。

---

<a id="ux-06"></a>

## UX-06: Dynamic Type に追随しない固定フォントサイズ

**深刻度**: 🟡 Medium
**該当**: `src/Views/FlashcardView.swift:135, 305, 316, 343, 403`

```swift
.font(.system(size: 32, weight: .black, design: .rounded))   // 単語パターン
.font(.system(size: 20, weight: .bold, design: .rounded))    // 問題パターン
.font(.system(size: 19, weight: .medium, design: .rounded))  // 穴埋め
```

`.font(.system(size:))` は **絶対サイズ**で、ユーザーが設定した文字サイズ（Dynamic Type）を無視します。文字を大きくして使っている高齢の学習者や弱視のユーザーにとって、カード本文だけが小さいまま固定されます。

なお `REQUIREMENTS.md 3.4-2` は「28pt rounded」と書いていますが実装は32ptで、要件と実装も食い違っています。

### 推奨対応

`relativeTo:` を使えばデザイン意図を保ったまま追随できます。

```swift
.font(.system(.largeTitle, design: .rounded).weight(.black))
// またはサイズ指定を残したい場合
.font(.custom("", size: 32, relativeTo: .largeTitle).weight(.black))
```

---

<a id="ux-07"></a>

## UX-07: `maxHeight: 520` のマジックナンバーが小型端末で破綻する

**深刻度**: 🟡 Medium
**該当**: `src/Views/FlashcardView.swift:245`

```swift
.frame(maxHeight: 520) // iPhone縦画面に最適な最大高さ (超過時スクロール)
```

iPhone SE (第2/第3世代) の画面高は **667pt** です。ここからセーフエリア・ナビゲーションバー・進捗バー・判定ボタン群（約120pt）・ヒントテキストを引くと、カードに使える領域は 520pt を大きく下回ります。結果、判定ボタンが画面外へ押し出されるか、レイアウトが潰れます。

Dynamic Type を最大にした場合も同様です。

### 推奨対応

固定値ではなく利用可能領域から決めてください。

```swift
GeometryReader { proxy in
    ...
    .frame(maxHeight: proxy.size.height * 0.72)
}
```

UX-01（ScrollViewの一本化）を行えば、この `maxHeight` 自体が不要になります。

---

<a id="ux-08"></a>

## UX-08: ダークモードで白背景をハードコードしている箇所がある

**深刻度**: 🟡 Medium
**該当**: `src/Views/FlashcardView.swift:535, 557`, `src/Views/CardStudyView.swift:157, 166, 175`

```swift
// FlashcardView.swift:535 — メモ編集の TextField
.background(Color.white)

// CardStudyView.swift:157 — スワイプヒントのオーバーレイ
.background(Color.white.opacity(0.9))
```

`REQUIREMENTS.md 4.1` は「ダークモード/ライトモード対応の curated HSL カラーパレット」を掲げていますが、これらは**モードに関わらず常に白**です。

- メモ編集欄: ダークモードでは白背景に `.primary`（＝白系）の文字が乗り、**文字が読めなくなります**
- スワイプヒント: 白背景に色付きテキストなのでコントラストは保たれますが、ダークモード中に白い矩形が唐突に現れて浮きます

なお、要件が謳う「curated HSL カラーパレット」に相当する定義はコード上に存在せず、SwiftUI標準色（`.blue` `.orange` `.purple`）＋ `opacity()` の組み合わせで構成されています。デザイントークンの一元管理を導入する価値があります。

### 推奨対応

```swift
// セマンティックカラーを使う
.background(Color(uiColor: .secondarySystemBackground))

// あるいは Assets.xcassets に Any/Dark 対応のカラーセットを定義し、
// Color("CardSurface") のように参照する（＝要件のcurated palette）
```

同ファイル `:557` の macOS フォールバック `return Color.white` も同様です。

---

<a id="ux-09"></a>

## UX-09: 進捗バーが最初のカードで既に100%を示す

**深刻度**: 🔵 Low
**該当**: `src/Views/CardStudyView.swift:38, 184`

```swift
progressHeader(current: currentIndex + 1, total: dueCards.count)
...
ProgressView(value: Double(current), total: Double(total))
```

`currentIndex` は0始まりなので、`current` は常に「今表示中のカードの番号」です。1枚しかないデッキでは開始直後に **1/1 = 100%** となり、まだ1枚も判定していないのにバーが満杯になります。10枚でも開始時点で10%進んだ表示です。

テキスト表示「1 / 10 カード」は正しいので、バーの値だけを「完了した枚数」に変えるのが自然です。

### 推奨対応

```swift
ProgressView(value: Double(currentIndex), total: Double(dueCards.count))
Text("\(currentIndex + 1) / \(dueCards.count) カード")
```

---

<a id="ux-10"></a>

## UX-10: マイメモが「保存」を押さずにカードを進めると消える

**深刻度**: 🟡 Medium
**該当**: `src/Views/FlashcardView.swift:510-528, 271-275`

メモは「編集」→ 入力 → 「保存」ボタンで初めて `onSaveNotes?(noteText)` が呼ばれます。保存せずに次のカードへ進むと `onChange(of: card.id)` が `noteText = card.userNotes` でリセットするため、**入力内容が無言で失われます**。

`REQUIREMENTS.md 3.3-⑤` は「その場で**即座に**メモのインライン編集・保存が可能」と定めており、明示的な保存ボタンを要求する現在の設計とはニュアンスが異なります。学習中に思いついた覚え方をメモするという用途上、消えるのは体験として痛手です。

### 推奨対応

- 入力の変化を都度伝搬する（`onChange(of: noteText)` でデバウンスして `onSaveNotes`）
- または、カード遷移時・編集モード終了時に自動保存する
- 最低限、未保存の状態でカードが変わる際は保存を実行してから切り替える

---

<a id="ux-11"></a>

## UX-11: 破壊的操作に確認がない（コース削除で全カードが即消滅）

**深刻度**: 🟡 Medium
**該当**: `src/Views/DeckListView.swift:441-446`, `src/Views/CourseContentView.swift:37-43`

```swift
// DeckListView.swift:441 — コンテキストメニューの「コースを削除」
Button(role: .destructive, action: {
    store.deleteCourse(course.id)      // ← 確認なしで即実行
})
```

コースの削除は**配下の全デッキ・全カード・全学習履歴の削除**を意味しますが、確認ダイアログもUndoもありません。コンテキストメニューは長押しで開くため、スクロール中の誤操作で開いてしまうことがあり、そのまま「削除」に触れる事故が起こりえます。

カードのスワイプ削除（`CourseContentView.swift:37`, `allowsFullSwipe: true`）も同様に即時削除です。フルスワイプは意図せず発火しやすい操作です。

同じファイルで、学習の中断には丁寧な3択 `confirmationDialog` を用意している（要件3.3-④）のと比べると、保護レベルが釣り合っていません。

### 推奨対応

```swift
.confirmationDialog("「\(course.title)」を削除しますか？",
                    isPresented: $isDeleteConfirmPresented, titleVisibility: .visible) {
    Button("削除する（カード\(course.totalCardsCount)枚も削除されます）", role: .destructive) {
        store.deleteCourse(course.id)
    }
    Button("キャンセル", role: .cancel) {}
}
```

カード削除は `allowsFullSwipe: false` にするか、削除後に取り消しトーストを出す設計が安全です。

---

<a id="ux-12"></a>

## UX-12: フォルダ未分類のコースにアクセスする手段がない

**深刻度**: 🟡 Medium
**該当**: `src/Views/DeckListView.swift:16, 29-35, 252-292`

```swift
// :16 コメント
// フォルダフィルターステート (nil = すべて, UUID.nil = 未分類, 特定UUID = 各フォルダ)
@State private var selectedFolderId: UUID? = nil
```

コメントは3状態（すべて / 未分類 / 各フォルダ）を想定していますが、`UUID?` 1つでは「すべて」と「未分類」を区別できず、**実際には2状態しかありません**。`folderChipsHeader`（:252）も「すべて」＋各フォルダのチップしか生成しません。

一方 `CreateCourseView.swift:65` は「未分類 (フォルダなし)」を明示的に選択肢として提供しており、`DeckStore` のサンプルデータにも `folderId: nil` のコースが2件存在します（世界史・化学基礎）。

結果、**未分類のコースは「すべて」タブでしか見えず、絞り込む手段がありません**。フォルダを増やすほど「すべて」が肥大化し、未分類のコースが埋もれます。

### 推奨対応

3状態を表現できる型に変えてください。

```swift
enum FolderFilter: Hashable {
    case all
    case unfiled
    case folder(UUID)
}
@State private var folderFilter: FolderFilter = .all

// フィルタ
switch folderFilter {
case .all:              return true
case .unfiled:          return course.folderId == nil
case .folder(let id):   return course.folderId == id
}
```

チップバーにも「未分類」を追加してください。

---

<a id="ux-13"></a>

## UX-13: ページネーションと横スクロールが二重になっており、ページ番号も範囲外になりうる

**深刻度**: 🟡 Medium
**該当**: `src/Views/DeckListView.swift:22, 51-62, 188-196, 313-373`

2つの問題があります。

**(a) ページャと横スクロールの二重化**

1ページ3件（`pageSize = 3`）に制限したうえで、その3件を**横スクロール**の `ScrollView(.horizontal)` に入れています（:188）。カード幅は240ptなので、iPhoneの画面幅には1.5枚程度しか収まりません。ユーザーは「横スクロールで3枚見る → ページ送りボタンで次の3枚」という二段階の操作を強いられます。

`REQUIREMENTS.md 3.1` の「コース数が多い場合は1ページ 3件ずつ表示」は満たしていますが、横スクロールがある以上ページ分割の必然性がなく、UXとしては素直に縦リスト（またはページャなしの横カルーセル）にしたほうが快適です。

**(b) ページ番号がクランプされない**

`currentPage` はフォルダ切替とソート変更時に1へ戻されますが（:258, :337）、**コースの削除・アーカイブ時にはリセットされません**。3ページ目を表示中に該当コースを全てアーカイブすると:

- `pagedCourses` は `startIndex < sortedCourses.count` のガードで `[]` を返す（:59）
- 画面には「該当するコースがありません」と表示される（:182）
- しかしページャは「3 / 1」のような不整合な表示のまま

ユーザーは「コースが消えた」と誤解します。

### 推奨対応

```swift
// クランプを計算プロパティ側で保証する
private var safePage: Int { min(max(1, currentPage), totalPages) }

// または .onChange(of: sortedCourses.count) { currentPage = min(currentPage, totalPages) }
```

(a) については、ページャを廃止して `LazyVStack` の縦リストに統一するか、`TabView(.page)` のページングカルーセルに寄せることを推奨します。

---

<a id="ux-14"></a>

## UX-14: テーマカラーが保存されるだけで一切描画に使われていない

**深刻度**: 🟡 Medium
**該当**: `src/Views/CreateCourseView.swift:25-27`, `src/Views/DeckListView.swift:383`, `src/Views/CourseDetailView.swift:121`

`Course` / `CourseFolder` は `themeColorHex` を持ち、サンプルデータも6色を丁寧に設定していますが:

- `CreateCourseView` の `availableColors`（7色の配列）は**宣言されているだけで、どのViewにも描画されていません**（:25）。カラーピッカーのUIが存在しないため、ユーザーは色を選べず、`selectedColorHex` は常に初期値 `#007AFF` のままです
- 表示側も `themeColorHex` を読まず、アイコン背景は `Color.blue` 固定です（`DeckListView.swift:383`, `CourseDetailView.swift:121`）

つまり **全コースが同じ青色**で表示されます。`REQUIREMENTS.md 2.2 / 3.1`「テーマカラー」の要件が、モデルにだけ存在してUIに到達していません。

さらに `REQUIREMENTS.md 3.1` が求める「**最終学習日時、更新日時の表示**」も `courseCard`（:376-447）には実装されておらず、表示されているのはアイコン・カード枚数・タイトル・説明のみです。ソート機能（最近学習した順／更新日順）はあるのに、その基準となる日付が見えないため、並び順の意味がユーザーに伝わりません。

### 推奨対応

```swift
// Color(hex:) のイニシャライザを追加し、
extension Color { init?(hex: String) { ... } }

// カード側で使う
.background(Color(hex: course.themeColorHex) ?? .blue)

// 日付も表示する
if let last = course.lastStudiedAt {
    Text("最終学習: \(last.formatted(.relative(presentation: .named)))")
        .font(.caption2).foregroundStyle(.secondary)
}
```

`CreateCourseView` にはカラー選択グリッド（アイコン選択と同じ構造）を追加してください。

---

<a id="ux-15"></a>

## UX-15: 穴埋めの `[...]` パターンが通常の角括弧テキストを誤ってマスクする

**深刻度**: 🟡 Medium
**該当**: `src/Views/FlashcardView.swift:334`

```swift
let clozePattern = #"\{\{(.*?)\}\}|\[(.*?)\]"#
```

`[...]` を穴埋め記法として扱っていますが、角括弧は技術系の学習内容で頻出します。

- プログラミング: `array[0]`, `dict["key"]`, `List[int]`
- 数学・化学: `[H+]`（水素イオン濃度）, `[0, 1]`（閉区間）
- 一般的な注記: `[注]`, `[重要]`, `[出典]`

これらを含むカードを `cloze` タイプで作ると、意図しない箇所が伏せ字になります。本プロジェクトはGoogle Cloud ACEや基本情報技術者のカードを主要なサンプルにしているため、遭遇確率は高いです。

また、マスク処理が **マッチ全体から `{`, `}`, `[`, `]` を単純に文字列置換**しているため（:360-363）、単語自体に括弧を含むケースも壊れます。

```swift
let matchedWord = nsString.substring(with: matchRange)
    .replacingOccurrences(of: "{", with: "")   // 中身の括弧まで消える
    ...
```

### 推奨対応

- 記法を `{{...}}` のみに統一する（`[...]` のサポートを落とす）ことを推奨します。`REQUIREMENTS.md 3.4-3` は両方を許容していますが、実用上の衝突コストが利点を上回ります
- `[...]` を残すなら、キャプチャグループ（`match.range(at: 1)` / `at: 2`）から中身を取り出し、文字列置換をやめてください

```swift
let inner = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
let matchedWord = nsString.substring(with: inner)
```

---

<a id="ux-16"></a>

## UX-16: 穴埋めヒントが全ての空欄を同時に開示する

**深刻度**: 🔵 Low
**該当**: `src/Views/FlashcardView.swift:373-387`

`showHint` はビュー全体で1つの `Bool` なので、1箇所をタップすると **文中の全ての空欄の頭文字が一斉に露出**します。

`.scratch/expert-improvements/spec.md` は「**伏せ字バッジをタップした時だけ** 先頭1文字目をヒント開示（自力想起の最大化）」と設計意図を明記しています。複数の空欄を持つ文で1つだけヒントが欲しい場合、他の答えまで見えてしまい、想起の負荷が下がって学習効果が落ちます。

なお、`Text` を `+` で連結した `combinedText` にはタップ位置の情報がないため（:398, :406）、現状の実装方式では個別タップを取れません。

### 推奨対応

空欄ごとに独立したビューへ分解し、インデックス単位でヒント状態を持ってください。

```swift
@State private var revealedHintIndices: Set<Int> = []

// レイアウトは WrappingHStack 相当、または Text の代わりに
// 各要素を Button 化した FlowLayout (iOS 16+ の Layout プロトコル) で構成する
```

`onChange(of: card.id)` でのリセット（:271-275）も `revealedHintIndices.removeAll()` に置き換えてください。
