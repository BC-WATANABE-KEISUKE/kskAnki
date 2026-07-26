# ADR-0001: SwiftUIを用いたNative iOSアプリの採用

- **ステータス**: 承認済み (Accepted)
- **日付**: 2026-07-26
- **意思決定者**: ユーザー & Antigravity

## 背景・課題 (Context)
iPhone上での快適な学習体験、スワイプアニメーション、サクサク動く動作速度、Haptics（触覚フィードバック）を実現するために、アプリケーションの技術スタックを決定する必要があった。

## 検討した選択肢 (Options Considered)
1. **SwiftUI Native iOS App (Swift / SwiftData)**
2. **Mobile-First Web App / PWA (Next.js / React)**
3. **Flutter / React Native (Cross Platform)**

## 決定事項 (Decision)
**1. SwiftUI Native iOS App** を採用する。

### 採用理由
- iPhoneでのタッチレスポンス、カードめくりスワイプアニメーション、Haptics（触覚効果）のクオリティが最も高い。
- iOS 17/18最新のSwiftDataによるスマートなローカルストレージ・キャッシュ管理が可能。
- 将来的にiOS Widgetやバックグラウンド学習リマインダー通知などを実装しやすい。

## 影響・トレードオフ (Consequences)
- iOS専用となるため、Webブラウザからの直接アクセスは不可（将来必要になった場合はバックエンドAPI連携で拡張する）。
- Xcode / Swift Package Manager (SPM) 環境ベースでコード・パッケージ管理を行う。
