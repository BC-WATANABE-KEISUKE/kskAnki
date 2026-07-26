import Foundation
import AVFoundation
import NaturalLanguage

/// 音声読み上げ (TTS) & 音声ファイル再生サービス (AUDIO-01: 高精度言語推定・マナーモード配慮・AVAudioSession セッション解放適合)
@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class AudioService: NSObject, AVSpeechSynthesizerDelegate, Sendable {
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
        let langCode = (language != nil && !language!.isEmpty) ? language! : detectLanguage(for: text)
        utterance.voice = AVSpeechSynthesisVoice(language: langCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // AUDIO-01: .ambient カテゴリによりマナーモード（消音スイッチ）の設定を尊重
            try session.setCategory(.ambient, mode: .spokenAudio, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
        #endif
        
        synthesizer.speak(utterance)
    }
    
    /// AVSpeechSynthesizerDelegate: 読み上げ終了時に AVAudioSession を解放
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        #if os(iOS)
        Task { @MainActor in
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }
    
    /// 音声URL / ファイルを再生する
    public func playAudio(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        player = AVPlayer(url: url)
        player?.play()
    }
    
    /// NaturalLanguage (NLLanguageRecognizer) による高精度言語自動検出 (AUDIO-01)
    private func detectLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        
        if let detectedLang = recognizer.dominantLanguage {
            switch detectedLang {
            case .english:
                return "en-US"
            case .japanese:
                return "ja-JP"
            case .simplifiedChinese, .traditionalChinese:
                return "zh-CN"
            case .french:
                return "fr-FR"
            case .german:
                return "de-DE"
            case .spanish:
                return "es-ES"
            default:
                break
            }
        }
        
        // フォールバック判定
        let latinCount = text.unicodeScalars.filter { scalar in
            (scalar.value >= 0x0041 && scalar.value <= 0x005A) || (scalar.value >= 0x0061 && scalar.value <= 0x007A)
        }.count
        
        return (Double(latinCount) / Double(max(1, text.count)) > 0.3) ? "en-US" : "ja-JP"
    }
}
