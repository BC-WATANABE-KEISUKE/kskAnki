# kskAnki

Ankiカードの生成・学習・管理を効率化・高度化するためのアプリケーションプロジェクト。

## 📁 ディレクトリ構成 (Directory Structure)

```text
kskAnki/
├── CONTEXT.md               # ドメインモデル・用語集・プロジェクト基本方針
├── docs/                    # 各種ドキュメント
│   ├── adr/                 # Architecture Decision Records (技術的・構造的決定事項)
│   ├── specs/               # 要件定義書・PRD・機能仕様書
│   └── design/              # UI/UXデザイン案、システム設計、シーケンス図など
├── .scratch/                # タスク管理・開発時スクラッチ（機能ごとのspec/issue）
│   └── <feature-slug>/
│       ├── spec.md
│       └── issues/
│           └── 01-<ticket-slug>.md
├── src/                     # ソースコード本体
├── tests/                   # テストコード（ユニットテスト、統合テストなど）
├── README.md                # 本ファイル
└── .gitignore               # Git除外設定
```

## 🚀 開発の進め方 (Workflow)

1. **アイデア・要件の整理**: `docs/specs/` や `CONTEXT.md` にアプリのアイデア・目的・ドメイン用語を記述。
2. **設計・決定事項**: 重大な技術選定やアーキテクチャは `docs/adr/` に記録。
3. **タスク分解**: 実装機能ごとに `.scratch/<feature-slug>/` 以下に spec や issue を作成して開発を進める。
4. **実装 & テスト**: `src/` にコードを作成し、`tests/` にテストを作成して検証。
