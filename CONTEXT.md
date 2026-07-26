# Project Context & Domain Model

## 🎯 目的 (Overview)
`kskAnki` は、Anki（暗記カードソフトウェア）を活用した学習効率の最大化を図るためのツール・アプリケーション群です。

## 📖 ドメイン用語集 (Domain Glossary)

| 用語 (Term) | 説明 (Description) |
|---|---|
| **Deck** | Ankiの単語帳・カードコレクション単位。 |
| **Note** | 表面・裏面などのフィールド情報を持つ元のデータ単位。 |
| **Card** | Noteから生成される実際の出題カード（表面→裏面、裏面→表面など）。 |
| **Preset / Config** | 間隔反復（Spaced Repetition）アルゴリズムや学習設定。 |

## 🏗 アーキテクチャ基本方針
- 仕様優先・ドキュメント駆動開発（Spec & Docs First）
- コンポーネントおよびモジュールの疎結合化とテスタビリティの確保
