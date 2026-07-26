# 技術スタック選定提案 (Tech Stack Proposal)

iPhoneでの最高の学習体験・カード作成体験を目指す `kskAnki` の技術スタック比較とおすすめ構成の提案です。

---

## 📱 要件のポイント
1. **iPhoneでの操作感・表示に最適化されていること**
   - 快適なタッチ操作・スワイプアニメーション
   - 画面サイズ（Dynamic Island, Safe Areaなど）への完全対応
2. **学習効率とスピード**
   - オフラインでもサクサク動くこと
   - カード作成（AI自動生成、辞書連携など）が容易であること
3. **将来の拡張性**
   - Anki (AnkiMobile / AnkiConnect) とのデータ連携
   - バックグラウンド同期や通知

---

## 🏛 候補となるアーキテクチャ・技術スタック比較

| 構成 | フロントエンド | バックエンド / ストレージ | メリット | デメリット / 留意点 |
|---|---|---|---|---|
| **案A: Pure Native iOS (推奨)** | SwiftUI (Swift) | SwiftData / SQLite + (オプション) CloudAPI | ・iPhoneで**圧倒的に最高のUX/アニメーション**<br>・完全オフライン対応<br>・Haptics（振動）やWidget、通知との親和性 | ・Mac / Xcode環境が必要<br>・Webブラウザから直接開くことは不可 |
| **案B: Mobile-First Web / PWA** | React / Next.js or Vite | Supabase / Firebase / Cloudflare Workers | ・iPhone/Mac/PCのどれからでも使える<br>・即時更新可能<br>・Web標準技術で開発が高速 | ・SwiftUI特有の質感やネイティブ感には及ばない<br>・オフライン制限 |
| **案C: ハイブリッド (SwiftUI + WebAPI)** | Native SwiftUI (iOS) | Hono / FastAPI / Cloudflare (カード生成・AI用) | ・最高のUI体験 + クラウドのAI自動カード生成機能を融合 | ・フロントとバックエンドの両方管理が必要 |

---

## ⭐️ Antigravityのおすすめ提案

### **【本命】案A または 案C（SwiftUI ベースのネイティブ iOS アプリ）**

**理由**:
暗記アプリ（Anki系）において、iPhoneでの「毎日の学習の快適さ（スワイプ感、触覚フィードバック、瞬間的なレスポンス）」は継続率に直結します。SwiftUIであれば、iOS 17/18最新のUIコンポーネント（SwiftDataによるシンプルなローカルデータベース管理、SwiftUIのモディファイア）をフル活用できます。

#### おすすめ構成案
- **UI Framework**: SwiftUI (iOS 17+ Target)
- **データ永続化**: SwiftData (または GRDB / SQLite)
- **AI / 外部連携 (必要な場合)**:
  - ローカル処理: Swift / Foundation
  - 外部処理: OpenAI / Gemini API または 自作バックエンド (Hono / Cloudflare Workers)
