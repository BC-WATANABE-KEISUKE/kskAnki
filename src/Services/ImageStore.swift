import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// カードアタッチメント用ローカル画像永続化＆ロードサービス (UI-03 / UI-04 / SEC-03)
public struct ImageStore: Sendable {
    
    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }
    
    /// 画像データを Documents/CardImages ディレクトリに保存し、相対ファイル名を返す
    public static func saveImage(data: Data) throws -> String {
        let folderURL = documentsDirectory.appendingPathComponent("CardImages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        
        let fileName = "\(UUID().uuidString).jpg"
        let fileURL = folderURL.appendingPathComponent(fileName)
        // SEC-03: completeFileProtection オプションでデバイス暗号化保護を適用
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        
        return "CardImages/\(fileName)"
    }
    
    /// 相対パスまたはフルパスから画像データを読み込む
    #if canImport(UIKit)
    public static func loadImage(path: String) -> UIImage? {
        if path.hasPrefix("/") {
            return UIImage(contentsOfFile: path)
        } else if path.hasPrefix("file://"), let url = URL(string: path) {
            return UIImage(contentsOfFile: url.path)
        } else {
            let fullURL = documentsDirectory.appendingPathComponent(path)
            return UIImage(contentsOfFile: fullURL.path)
        }
    }
    #endif
}
