import Foundation
import CoreGraphics

/// SRS 定数パラメータおよびスワイプ閾値などの一元管理構造体 (CLN-04)
public struct SRSParameters: Sendable {
    // SRS (SuperMemo SM-2 拡張) 定数
    public static let defaultEaseFactor: Double = 2.5
    public static let minEaseFactor: Double = 1.3
    public static let maxIntervalDays: Int = 365
    
    // UI スワイプ判定パラメータ
    public static let swipeThresholdWidth: CGFloat = 90.0
    public static let swipeRatioLimit: CGFloat = 1.5
    
    // 制限・キャパシティ定数
    public static let csvImportLimit: Int = 2000
    public static let maxStudyLogsCapacity: Int = 10000
}
