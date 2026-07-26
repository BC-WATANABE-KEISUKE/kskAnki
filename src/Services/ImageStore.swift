import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

/// カードアタッチメント用ローカル画像永続化＆ロードサービス (UI-03 / UI-04 / SEC-03 / PERF-05 ダウンサンプリング最適化 & NSCache)
public final class ImageStore: Sendable {
    
    #if canImport(UIKit)
    private static let imageCache = NSCache<NSString, UIImage>()
    #endif
    
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
        let cacheKey = path as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }
        
        let fileURL = getURL(for: path)
        guard let image = UIImage(contentsOfFile: fileURL.path) else { return nil }
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }
    
    /// PERF-05: 高解像度画像を直接メインメモリに解凍せず表示サイズへ低メモリデコード＆NSCache保持するダウンサンプリング API
    public static func loadDownsampledImage(path: String, pointSize: CGSize, scale: CGFloat = 2.0) -> UIImage? {
        let cacheKey = "\(path)_\(pointSize.width)x\(pointSize.height)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }
        
        let fileURL = getURL(for: path)
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, imageSourceOptions) else {
            return nil
        }
        
        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }
        
        let resultImage = UIImage(cgImage: downsampledImage)
        imageCache.setObject(resultImage, forKey: cacheKey)
        return resultImage
    }
    #endif
    
    private static func getURL(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        } else if path.hasPrefix("file://"), let url = URL(string: path) {
            return url
        } else {
            return documentsDirectory.appendingPathComponent(path)
        }
    }
}
