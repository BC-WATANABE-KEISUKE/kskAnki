import Foundation

/// 学習対象のフィルター条件 (SRS 期日ベース制御対応)
public enum StudyFilterTarget: String, CaseIterable, Identifiable, Sendable {
    case dueToday = "今日が復習日のもの（推奨・SRS）"
    case overdue = "復習期日を超過しているもの"
    case all = "すべてのカード"
    case notMasteredFourTimes = "4回連続◯未達成のみ (4連勝除外)"
    case unlearned = "未学習のものだけ"
    
    // 日時ベースの判定
    case studiedToday = "今日学習したもの"
    case studiedYesterday = "昨日学習したもの"
    case studiedWithinOneWeek = "1週間以内に学習したもの"
    
    // 前回学習時の判定
    case wrongTriangleLastTime = "前回「△」のもの"
    case wrongCrossLastTime = "前回「✕」のもの"
    case wrongTriangleOrCrossLastTime = "前回「△」または「✕」"
    
    // 過去累計（一度でも...）の判定
    case everTriangle = "一度でも「△」をつけたもの"
    case everCross = "一度でも「✕」をつけたもの"
    case everTriangleOrCross = "一度でも「△」または「✕」をつけたもの"
    
    case favorites = "お気に入りのみ"
    
    public var id: String { self.rawValue }
    
    public var description: String {
        switch self {
        case .dueToday:
            return "SRS(間隔反復)アルゴリズムに基づき、本日が復習期日に該当するカード（復習期日到達または超過）"
        case .overdue:
            return "復習期日を過ぎてしまっているカード"
        case .all:
            return "登録されている全カードを対象にします"
        case .notMasteredFourTimes:
            return "4回連続で「◯ (正解)」評価を達成していないカードのみ（完全習得済みカードを除外）"
        case .unlearned:
            return "まだ一度も復習・学習していないカードだけを学習します"
        case .studiedToday:
            return "本日（今日）復習・学習を実施したカード"
        case .studiedYesterday:
            return "昨日復習・学習を実施したカード"
        case .studiedWithinOneWeek:
            return "直近1週間（過去7日間）以内に復習・学習したカード"
        case .wrongTriangleLastTime:
            return "直前の学習で「△ (惜しい)」と判定したカード"
        case .wrongCrossLastTime:
            return "直前の学習で「✕ (不正解)」と判定したカード"
        case .wrongTriangleOrCrossLastTime:
            return "直前の学習で「△」または「✕」と判定したカード"
        case .everTriangle:
            return "過去の学習で一度でも「△ (惜しい)」をつけた実績のあるカード"
        case .everCross:
            return "過去の学習で一度でも「✕ (不正解)」をつけた実績のあるカード"
        case .everTriangleOrCross:
            return "過去の学習で一度でも「△」または「✕」をつけたことのあるカード"
        case .favorites:
            return "スター・お気に入りマークをつけたカード"
        }
    }
}

/// 1回の学習セッション設定
public struct StudyFilterConfig: Sendable {
    public var target: StudyFilterTarget
    public var batchSize: Int // 0 の場合は全件
    
    public init(target: StudyFilterTarget = .dueToday, batchSize: Int = 10) {
        self.target = target
        self.batchSize = batchSize
    }
    
    /// 与えられたカード配列から条件に合うカードをフィルタリング・抽出
    public func filterCards(_ cards: [AnkiCard], currentDate: Date = Date()) -> [AnkiCard] {
        let filtered: [AnkiCard]
        let todayStart = Calendar.current.startOfDay(for: currentDate)
        
        switch target {
        case .dueToday:
            // 未学習カード または 次回復習期日が本日以前のカード
            filtered = cards.filter { card in
                card.isUnlearned || Calendar.current.startOfDay(for: card.dueDate) <= todayStart
            }
        case .overdue:
            // 復習期日が本日より前のカード
            filtered = cards.filter { card in
                !card.isUnlearned && Calendar.current.startOfDay(for: card.dueDate) < todayStart
            }
        case .all:
            filtered = cards
        case .notMasteredFourTimes:
            filtered = cards.filter { !$0.isFullyMasteredActive }
        case .unlearned:
            filtered = cards.filter { $0.isUnlearned }
        case .studiedToday:
            filtered = cards.filter { $0.isStudiedToday }
        case .studiedYesterday:
            filtered = cards.filter { $0.isStudiedYesterday }
        case .studiedWithinOneWeek:
            filtered = cards.filter { $0.isStudiedWithinOneWeek }
        case .wrongTriangleLastTime:
            filtered = cards.filter { $0.isWrongTriangleLastTime }
        case .wrongCrossLastTime:
            filtered = cards.filter { $0.isWrongCrossLastTime }
        case .wrongTriangleOrCrossLastTime:
            filtered = cards.filter { $0.isWrongTriangleOrCrossLastTime }
        case .everTriangle:
            filtered = cards.filter { $0.hasEverBeenTriangle }
        case .everCross:
            filtered = cards.filter { $0.hasEverBeenCross }
        case .everTriangleOrCross:
            filtered = cards.filter { $0.hasEverBeenTriangleOrCross }
        case .favorites:
            filtered = cards.filter { $0.isFavorite }
        }
        
        if batchSize > 0 && batchSize < filtered.count {
            return Array(filtered.prefix(batchSize))
        }
        return filtered
    }
}
