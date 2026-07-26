import SwiftUI

/// アプリ設定画面 (SEC-01: Keychain キー暗号化保存 / FEAT-03: バックアップ対応)
@available(iOS 17.0, macOS 14.0, *)
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // 設定ステート
    @AppStorage("dailyReviewLimit") private var dailyReviewLimit: Int = 50
    @AppStorage("enableAutoAudio") private var enableAutoAudio: Bool = true
    @AppStorage("enableHaptics") private var enableHaptics: Bool = true
    
    // SEC-01: Keychain キー暗号化保管ステート
    @State private var apiKeyInput: String = ""
    
    // FEAT-03: バックアップステート
    @State private var backupJSONText: String = ""
    @State private var isBackupSheetPresented: Bool = false
    @State private var feedbackMessage: String? = nil
    
    public let store: DeckStore?
    
    public init(store: DeckStore? = nil) {
        self.store = store
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // 1. 学習設定
                Section {
                    Stepper("1日の復習上限: \(dailyReviewLimit) 枚", value: $dailyReviewLimit, in: 10...200, step: 10)
                    Toggle("カードめくり時の音声自動再生", isOn: $enableAutoAudio)
                    Toggle("触覚フィードバック (Haptics)", isOn: $enableHaptics)
                } header: {
                    Text("学習・復習設定")
                } footer: {
                    Text("毎日の復習カード数の上限や操作感を設定します。")
                }
                
                // 2. AI機能設定 (SEC-01: Keychain への安全保存)
                Section {
                    SecureField("OpenAI / Gemini API Key", text: $apiKeyInput)
                        .onChange(of: apiKeyInput) { _, newValue in
                            KeychainStore.save(key: "openAIApiKey", value: newValue)
                        }
                } header: {
                    Text("AIカード自動生成 (Keychain暗号化管理)")
                } footer: {
                    Text("APIキーはデバイスの安全な Keychain 内に暗号化保存されます。")
                }
                
                // 3. データバックアップ & 復元 (FEAT-03)
                if let store = store {
                    Section {
                        Button("JSON バックアップを出力・コピー") {
                            if let json = BackupService.exportBackupJSON(store: store) {
                                backupJSONText = json
                                #if canImport(UIKit)
                                UIPasteboard.general.string = json
                                #endif
                                feedbackMessage = "全データのJSONバックアップをクリップボードにコピーしました！"
                                isBackupSheetPresented = true
                            }
                        }
                    } header: {
                        Text("データバックアップ & 復元 (FEAT-03)")
                    } footer: {
                        if let msg = feedbackMessage {
                            Text(msg).foregroundColor(.blue)
                        } else {
                            Text("コースやカード、学習ログを含む全データをJSON形式でバックアップ・復元できます。")
                        }
                    }
                }
                
                // 4. アプリ情報
                Section {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text("1.0.0 (Build 1)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("アルゴリズム")
                        Spacer()
                        Text("SuperMemo SM-2 (3択拡張版)")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("アプリ情報")
                }
            }
            .navigationTitle("設定")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isBackupSheetPresented) {
                NavigationStack {
                    ScrollView {
                        Text(backupJSONText)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                    }
                    .navigationTitle("JSON バックアップ")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { isBackupSheetPresented = false }
                        }
                    }
                }
            }
            .onAppear {
                apiKeyInput = KeychainStore.load(key: "openAIApiKey") ?? ""
            }
        }
    }
}
