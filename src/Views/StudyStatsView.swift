import SwiftUI

/// 暗記学習の統計ダッシュボード画面 (FEAT-02: 過去7日間の学習数・理解度内訳の可視化)
@available(iOS 17.0, macOS 14.0, *)
public struct StudyStatsView: View {
    @Environment(\.dismiss) private var dismiss
    public let store: DeckStore
    
    public init(store: DeckStore) {
        self.store = store
    }
    
    private var calendar: Calendar { Calendar.current }
    
    // 過去7日間の日付と学習枚数の配列
    private var last7DaysStats: [(date: Date, label: String, count: Int)] {
        let today = calendar.startOfDay(for: Date())
        var results: [(Date, String, Int)] = []
        
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d(eee)"
        formatter.locale = Locale(identifier: "ja_JP")
        
        for i in (0..<7).reversed() {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                let count = store.studyLogs.filter { calendar.isDate($0.studiedAt, inSameDayAs: date) }.count
                let label = i == 0 ? "今日" : formatter.string(from: date)
                results.append((date, label, count))
            }
        }
        return results
    }
    
    // 判定別の割合
    private var ratingCounts: (correct: Int, doubtful: Int, incorrect: Int) {
        var c = 0, d = 0, i = 0
        for log in store.studyLogs {
            switch log.rating {
            case .correct: c += 1
            case .doubtful: d += 1
            case .incorrect: i += 1
            }
        }
        return (c, d, i)
    }
    
    private var maxDailyCount: Int {
        max(1, last7DaysStats.map(\.count).max() ?? 1)
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. サマリー指標グリッド
                    summaryGrid
                    
                    // 2. 過去7日間の学習推移グラフ (バーチャート)
                    weeklyChartCard
                    
                    // 3. 理解度内訳 (◯ / △ / ✕)
                    ratingBreakdownCard
                }
                .padding(20)
            }
            .background(backgroundColor)
            .navigationTitle("学習統計 & 分析")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
    
    // 1. メイン指標カード一覧
    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statMetricCard(
                title: "連続学習日数",
                value: "\(store.streakDaysCount) 日",
                icon: "flame.fill",
                color: .orange
            )
            
            statMetricCard(
                title: "本日の学習枚数",
                value: "\(store.todayStudiedCardsCount) 枚",
                icon: "checkmark.seal.fill",
                color: .blue
            )
            
            statMetricCard(
                title: "総コース数",
                value: "\(store.courses.count) コース",
                icon: "books.vertical.fill",
                color: .purple
            )
            
            statMetricCard(
                title: "累計学習セッション",
                value: "\(store.studyLogs.count) 回",
                icon: "chart.line.uptrend.xyaxis",
                color: .green
            )
        }
    }
    
    private func statMetricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(cardBgColor)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
    
    // 2. 過去7日間の縦棒グラフ
    private var weeklyChartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("直近7日間の学習枚数推移", systemImage: "chart.bar.fill")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(last7DaysStats, id: \.label) { stat in
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
                                    .frame(height: max(6, geo.size.height * CGFloat(stat.count) / CGFloat(maxDailyCount)))
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
        let total = max(1, ratingCounts.correct + ratingCounts.doubtful + ratingCounts.incorrect)
        let correctRatio = Double(ratingCounts.correct) / Double(total)
        let doubtfulRatio = Double(ratingCounts.doubtful) / Double(total)
        let incorrectRatio = Double(ratingCounts.incorrect) / Double(total)
        
        return VStack(alignment: .leading, spacing: 16) {
            Label("理解度・解答判定内訳", systemImage: "piechart.fill")
                .font(.headline)
            
            // 積み上げプログレスバー
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
                legendItem(label: "◯ 正解 (\(ratingCounts.correct))", color: .green)
                legendItem(label: "△ 惜しい (\(ratingCounts.doubtful))", color: .orange)
                legendItem(label: "✕ 不正解 (\(ratingCounts.incorrect))", color: .red)
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
