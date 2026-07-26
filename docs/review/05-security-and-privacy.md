# 05. セキュリティ & プライバシー

---

<a id="sec-01"></a>

## SEC-01: APIキーが平文で UserDefaults に保存される

**深刻度**: 🟠 High
**該当**: `src/Views/SettingsView.swift:12, 32`

```swift
@AppStorage("openAIApiKey") private var openAIApiKey: String = ""
...
SecureField("OpenAI / Gemini API Key", text: $openAIApiKey)
```

`@AppStorage` は `UserDefaults` のラッパーであり、実体はアプリコンテナ内の **平文 plist ファイル** (`Library/Preferences/<bundle-id>.plist`) です。`SecureField` は画面上で文字を伏せるだけで、保存の安全性には一切関与しません。

リスク:

- 端末バックアップ（暗号化なしのローカルバックアップ、iCloudバックアップ）にAPIキーが平文で含まれます
- 脱獄端末やファイルシステムにアクセスできる状況で読み出されます
- App Store のプライバシー審査、および OpenAI / Google の利用規約における鍵の取り扱い義務に照らして不適切です

**APIキーは課金に直結する認証情報**です。漏洩すれば第三者がユーザーの請求で API を使用できます。

### 推奨対応

Keychain に保存してください。iOS 17 時点では `Security` フレームワークを直接叩くか、薄いラッパーを1つ用意するのが標準的です。

```swift
enum KeychainStore {
    static func set(_ value: String, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,  // バックアップに含めない
            kSecValueData as String: Data(value.utf8)
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }
    static func get(_ key: String) -> String? { ... }
}
```

`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` を指定すると、バックアップ経由での持ち出しも防げます。

**さらに根本的な指摘**: そもそも AI カード自動生成機能は実装されていません（[ARC-05](02-architecture-and-data.md#arc-05)）。**使われない秘密情報を保管しないのが最も安全**です。機能実装まで、この設定項目自体を削除することを推奨します。

なお、クライアントアプリに API キーを持たせる構成自体、ユーザーに鍵の調達を強いる点でも、鍵が端末上に存在する点でも一般には推奨されません。`docs/specs/tech-stack-proposal.md` の「案C: ハイブリッド（SwiftUI + WebAPI）」のように、生成処理を自前バックエンドへ寄せる設計を検討してください。

---

<a id="sec-02"></a>

## SEC-02: 任意のリモートURLを取得する経路があり、ATS で失敗する

**深刻度**: 🟡 Medium
**該当**: `src/Views/AddCardView.swift:113, 152`, `src/Views/FlashcardView.swift:453`, `src/Services/AudioService.swift:41-45`

カード追加・編集フォームは「画像Web URL (カンマ区切り)」という入力欄を提供し、そのURLが `AsyncImage` / `AVPlayer` にそのまま渡されます。

```swift
// AudioService.swift:41
public func playAudio(urlString: String) {
    guard let url = URL(string: urlString) else { return }
    player = AVPlayer(url: url)
    player?.play()
}
```

問題点:

1. **ATS (App Transport Security)**: iOS はデフォルトで平文HTTP通信を禁止します。ユーザーが `http://` のURLを貼ると、**何のエラー表示もなく画像が出ません**（`AsyncImage` の `.failure` は汎用アイコンを出すのみ、`AVPlayer` は無言で失敗）。UIが「Web URL」を明示的に促している以上、この失敗は頻発します。
2. **スキーム検証がない**: `URL(string:)` は `file://` や任意のスキームを受け付けます。`AVPlayer` に予期しないURLを渡す経路が開いています。
3. **サイズ・タイムアウト制限がない**: 巨大な画像URLを指定するとメモリを圧迫します。`AsyncImage` にはダウンサンプリング機構がありません。
4. **プライバシー**: リモートURLを読み込むたびに、そのホストへ利用者のIPアドレスとタイミング情報が送られます。学習内容を推測しうるトラッキング面が生まれます。

### 推奨対応

- 入力を `https` スキームに限定し、非対応の入力はフォーム上でエラー表示する

```swift
guard let url = URL(string: urlString), url.scheme == "https" else { return }
```

- 取り込み時にローカルへコピーし、以降はローカル参照にする（UX-04のオフライン対応と同じ方向）
- ATS 例外（`NSAllowsArbitraryLoads`）を Info.plist に追加して解決しようとしないでください。App Store 審査で正当な理由の説明を求められ、セキュリティ姿勢としても後退します

---

<a id="sec-03"></a>

## SEC-03: `AVAudioSession` を毎回設定し、解放しない

**深刻度**: 🟡 Medium
**該当**: `src/Services/AudioService.swift:32-35`

```swift
public func speak(text: String, language: String? = nil) {
    ...
    #if os(iOS)
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
    try? AVAudioSession.sharedInstance().setActive(true)
    #endif
    synthesizer.speak(utterance)
}
```

3つの問題があります。

1. **`setActive(false)` が呼ばれない**: 一度学習を始めると、アプリを終了するまでオーディオセッションがアクティブなままです。他アプリ（音楽・ポッドキャスト）の再生に影響が残り続けます。`AVSpeechSynthesizerDelegate` は既に採用済み（`AudioService.swift:7`）なのに、`speechSynthesizer(_:didFinish:)` が実装されておらず、終了フックが使われていません。
2. **`.playback` カテゴリは消音スイッチを無視します**: サイレントモードにしている電車内・図書館で、裏面を開いた瞬間に音声が流れます（自動再生は `FlashcardView.swift:259` で無条件実行、[ARC-05](02-architecture-and-data.md#arc-05)）。ユーザーの明確な意図（消音）を上書きする挙動は、レビューで低評価に直結します。
3. **発話のたびにセッション設定を行う**: 冗長で、他アプリの再生状態に毎回干渉します。

### 推奨対応

```swift
// 設定は1回だけ。カテゴリは用途に応じて選ぶ
private func activateSessionIfNeeded() {
    guard !isSessionActive else { return }
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
    isSessionActive = true
}

// 発話完了で解放
public func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    isSessionActive = false
}
```

消音スイッチを尊重するなら `.ambient` を使うか、設定で切り替えられるようにしてください。学習用途では「消音でも読み上げたい」ニーズもあるため、`enableAutoAudio` とは別の明示的な設定にする価値があります。

---

<a id="sec-04"></a>

## SEC-04: 音声ファイルURLを設定するUIが存在しない（デッドフィールド）

**深刻度**: 🔵 Low
**該当**: `src/Models/AnkiCard.swift:70-71`, `src/Views/FlashcardView.swift:280, 290`

`AnkiCard.frontAudioURL` / `backAudioURL` は再生側でのみ参照され（`FlashcardView.swift:280, 290`）、**値を設定するUIがどこにもありません**。`AddCardView` / `EditCardView` のどちらにも音声URLの入力欄がなく、CSV取り込みの列定義にも含まれていません。

したがって常に `nil` で、TTS フォールバックしか動作しません。`REQUIREMENTS.md 3.7`「添付音声URLがある場合は `AVPlayer` で音声再生」は**到達不能なコードパス**です。

セキュリティ観点では「使われないネットワーク取得経路が残っている」ことの指摘ですが、実質は仕様と実装の乖離です。

### 推奨対応

音声添付を実装するか、フィールドと再生分岐を削除してください。中途半端に残すと、後から SEC-02 と同じ検証漏れを持ち込む温床になります。

---

<a id="sec-05"></a>

## SEC-05: 写真ライブラリの利用目的の記述が必要になる

**深刻度**: 🔵 Low（BLK-01の対応時に必須）
**該当**: `src/Views/AddCardView.swift:115`, `src/Views/EditCardView.swift:103`

`PhotosPicker`（PHPicker ベース）はアプリ外プロセスで動作するため、**`NSPhotoLibraryUsageDescription` は必須ではありません**。この点で現在の実装は適切です。

ただし、UX-03 の対応で画像をアプリ内に保存する際、および将来的に `PHPhotoLibrary` へ直接アクセスする機能（アルバム一覧、書き出し等）を追加する場合には、Info.plist への用途説明が必須になります。App Store 審査でも用途の妥当性が確認されます。

BLK-01 で Info.plist を作成する際に、以下を検討事項として控えておいてください。

- `NSPhotoLibraryUsageDescription`: `PHPhotoLibrary` 直接アクセスを追加する場合のみ必要
- `NSPhotoLibraryAddUsageDescription`: カード画像を写真アプリへ保存する機能を追加する場合に必要
- App Privacy（プライバシーマニフェスト `PrivacyInfo.xcprivacy`）: `UserDefaults` の利用は Required Reason API に該当するため、**2024年春以降のApp Store提出には申告が必須**です。現状 `@AppStorage` を使用しているため対応が必要になります
