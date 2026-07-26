import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 画像フルスクリーン拡大ビューアーモーダル (UI-04: ローカル/リモート両対応 & ピンチズーム・ダブルタップ)
@available(iOS 17.0, macOS 14.0, *)
public struct ImageDetailView: View {
    @Environment(\.dismiss) private var dismiss
    public let urlString: String
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    public init(urlString: String) {
        self.urlString = urlString
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if urlString.hasPrefix("http://") || urlString.hasPrefix("https://"), let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        case .success(let image):
                            zoomableImageView(image)
                        case .failure:
                            failureView
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    #if canImport(UIKit)
                    if let uiImage = ImageStore.loadImage(path: urlString) {
                        zoomableImageView(Image(uiImage: uiImage))
                    } else {
                        failureView
                    }
                    #else
                    failureView
                    #endif
                }
            }
            .navigationTitle("拡大表示")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                }
            }
        }
    }
    
    private func zoomableImageView(_ image: Image) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = max(1.0, min(scale * delta, 4.0))
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            if scale <= 1.0 {
                                withAnimation {
                                    offset = .zero
                                }
                            }
                        },
                    DragGesture()
                        .onChanged { value in
                            if scale > 1.0 {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    if scale > 1.0 {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 2.5
                    }
                }
            }
    }
    
    private var failureView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("画像を読み込めませんでした")
                .foregroundColor(.white)
        }
    }
}
