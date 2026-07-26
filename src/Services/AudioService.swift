import Foundation
import AVFoundation

/// 音声読み上げ (TTS) & 音声ファイル再生サービス
@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class AudioService: NSObject, AVSpeechSynthesizerDelegate {
    public static let shared = AudioService()
    
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVPlayer?
    
    override private init() {
        super.init()
        synthesizer.delegate = self
    }
    
    /// テキストを合成音声 (TTS) で読み上げる
    public func speak(text: String, language: String? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        let langCode = language ?? detectLanguage(for: text)
        utterance.voice = AVSpeechSynthesisVoice(language: langCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        
        synthesizer.speak(utterance)
    }
    
    /// 音声URL / ファイルを再生する
    public func playAudio(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        player = AVPlayer(url: url)
        player?.play()
    }
    
    /// テキストの内容から言語コード (en-US / ja-JP) を自動検出
    private func detectLanguage(for text: String) -> String {
        let latinCount = text.unicodeScalars.filter { scalar in
            (scalar.value >= 0x0041 && scalar.value <= 0x005A) || (scalar.value >= 0x0061 && scalar.value <= 0x007A)
        }.count
        
        if Double(latinCount) / Double(max(1, text.count)) > 0.3 {
            return "en-US" // 英語
        } else {
            return "ja-JP" // 日本語
        }
    }
}
