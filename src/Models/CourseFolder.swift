import Foundation

/// 複数のコースを束ねるフォルダモデル
public struct CourseFolder: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var iconName: String
    public var themeColorHex: String
    public var createdAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "folder.fill",
        themeColorHex: String = "#007AFF",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.themeColorHex = themeColorHex
        self.createdAt = createdAt
    }
}
