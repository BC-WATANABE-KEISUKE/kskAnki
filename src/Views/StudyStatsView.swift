import SwiftUI

/// 日別統計用モデル (PERF-01 高速化)
public struct DailyStatItem: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let label: String
    public let count: Int
}

/// 学習成果・グラフィック統計ダッシュボード (FEAT-02, PERF-01 最適化)
@available(iOS 17.0, macOS 14.0, *)
public struct StudyStatsView: View {
    @Environment(\.dismiss) private var dismiss
    public let store: DeckStore
    
    // PERF-01: キャッシュ保持ステート (1.04秒フリーズ解消)
    @State private var cachedLast7DaysStats: [DailyStatItem] = []
    @State private var cachedMaxDailyCount: Int = 1
    @State private var cachedRatingCounts: (correct: Int, doubtful: Int, incorrect: Int) = (0, 0, 0)
    
    public init(store: DeckStore) {
        self.store = store
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. サマリーメトリクスカード (連続日数 & 本日枚数 & 総カード数)
                    summaryMetricsCard
                    
                    // 2. 過去7日間の縦棒グラフ
                    weeklyChartCard
                    
                    // 3. 理解度判定の割合
                    ratingBreakdownCard
                }
                .padding(16)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("学習統計ダッシュボード")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .task {
                recalculateStats()
            }
        }
    }
    
    // PERF-01: 1回の O(n) ループで統計データを一括計算・再構築
    private func recalculateStats() {
        let calendar = Calendar.current
        let now = Date()
        
        // 過去7日間の日付キーを作成
        var dateList: [Date] = []
        var statsMap: [Date: Int] = [:]
        
        for i in (0..<7).reversed() {
            if let date = calendar.date(byAdding: .day, value: -i, to: now) {
                let startDay = calendar.startOfDay(for: date)
                dateList.append(startDay)
                statsMap[startDay] = 0
            }
        }
        
        var correct = 0
        var doubtful = 0
        var incorrect = 0
        
        // 全ログを1度だけ走査
        for log in store.studyLogs {
            let startDay = calendar.startOfDay(for: log.studiedAt)
            if statsMap[startDay] != nil {
                statsMap[startDay, default: 0] += 1
            }
            
            switch log.rating {
            case .correct:
                correct += 1
            case .doubtful:
                doubtful += 1
            case .incorrect:
                incorrect += 1
            }
        }
        
        let stats = dateList.map { date -> DailyStatItem in
            let label = date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: "ja_JP")))
            let count = statsMap[date] ?? 0
            return DailyStatItem(date: date, label: label, count: count)
        }
        
        let maxCount = max(1, stats.map(\.count).max() ?? 1)
        
        self.cachedLast7DaysStats = stats
        self.cachedMaxDailyCount = maxCount
        self.cachedRatingCounts = (correct, doubtful, incorrect)
    }
    
    // 1. サマリーカード
    private var summaryMetricsCard: some View {
        HStack(spacing: 16) {
            metricTile(
                icon: "flame.fill",
                iconColor: .orange,
                value: "\(store.streakDaysCount)日",
                label: "連続学習ストリーク"
            )
            
            metricTile(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                value: "\(store.todayStudiedCardsCount)枚",
                label: "本日の学習枚数"
            )
            
            metricTile(
                icon: "rectangle.stack.fill",
                iconColor: .blue,
                value: "\(store.allCardsCount)枚",
                label: "全単語数"
            )
        }
        .padding(16)
        .background(cardBgColor)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
    
    private func metricTile(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // 2. 過去7日間の縦棒グラフ
    private var weeklyChartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("直近7日間の学習枚数推移", systemImage: "chart.bar.fill")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(cachedLast7DaysStats) { stat in
                    VStack(spacing: 6) {
                        Text("\(stat.count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(stat.count > 0 ? .blue : .secondary)
                        
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(stat.count > 0 ? Color.blue : Color.gray.opacity(0.2))
                                    .frame(height: max(6, geo.size.height * CGFloat(stat.count) / CGFloat(cachedMaxDailyCount)))
                            }
                        }
                        .frame(height: 100)
                        
                        Text(stat.label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(cardBgColor)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
    
    // 3. 理解度判定の割合
    private var ratingBreakdownCard: some View {
        let total = max(1, cachedRatingCounts.correct + cachedRatingCounts.doubtful + cachedRatingCounts.incorrect)
        let correctRatio = Double(cachedRatingCounts.correct) / Double(total)
        let doubtfulRatio = Double(cachedRatingCounts.doubtful) / Double(total)
        let incorrectRatio = Double(cachedRatingCounts.incorrect) / Double(total)
        
        return VStack(alignment: .leading, spacing: 16) {
            Label("理解度・解答判定内訳", systemImage: "piechart.fill")
                .font(.headline)
            
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(correctRatio))
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: geo.size.width * CGFloat(doubtfulRatio))
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geo.size.width * CGFloat(incorrectRatio))
                }
                .cornerRadius(8)
                .clipped()
            }
            .frame(height: 14)
            
            HStack(spacing: 16) {
                legendItem(label: "◯ 正解 (\(cachedRatingCounts.correct))", color: .green)
                legendItem(label: "△ 惜しい (\(cachedRatingCounts.doubtful))", color: .orange)
                legendItem(label: "✕ 不正解 (\(cachedRatingCounts.incorrect))", color: .red)
            }
            .font(.caption)
        }
        .padding(20)
        .background(cardBgColor)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
    
    private func legendItem(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .fontWeight(.medium)
        }
    }
    
    private var backgroundColor: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color.gray.opacity(0.06)
        #endif
    }
    
    private var cardBgColor: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color.white
        #endif
    }
}
