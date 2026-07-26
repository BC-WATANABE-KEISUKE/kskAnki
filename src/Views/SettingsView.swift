import SwiftUI

/// アプリ設定画面 (SEC-01: Keychain キー暗号化保存 / NEW-06 / NEW-07: バックアップ復元対応)
@available(iOS 17.0, macOS 14.0, *)
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // 設定ステート
    @AppStorage("dailyReviewLimit") private var dailyReviewLimit: Int = 50
    @AppStorage("enableAutoAudio") private var enableAutoAudio: Bool = true
    @AppStorage("enableHaptics") private var enableHaptics: Bool = true
    
    // SEC-01 / NEW-06: Keychain キー暗号化保管ステート
    @State private var apiKeyInput: String = ""
    @State private var isApiKeySaved: Bool = false
    @State private var apiKeyFeedback: String? = nil
    
    // FEAT-03 / NEW-07: バックアップ & 復元ステート
    @State private var backupJSONText: String = ""
    @State private var restoreInputJSON: String = ""
    @State private var isExportSheetPresented: Bool = false
    @State private var isImportSheetPresented: Bool = false
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
                
                // 2. AI機能設定 (NEW-06: 1文字毎保存の廃止、明示的保存＆削除ボタンの配置)
                Section {
                    SecureField("OpenAI / Gemini API Key", text: $apiKeyInput)
                    
                    HStack(spacing: 12) {
                        Button(action: saveApiKey) {
                            HStack {
                                Image(systemName: "lock.doc.fill")
                                Text("Keychainに安全保存")
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.blue)
                        }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        Spacer()
                        
                        if isApiKeySaved {
                            Button(action: deleteApiKey) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("キーを削除")
                                }
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.red)
                            }
                        }
                    }
                } header: {
                    Text("AIカード自動生成 (Keychain暗号化管理)")
                } footer: {
                    if let fb = apiKeyFeedback {
                        Text(fb).foregroundColor(.blue)
                    } else {
                        Text("APIキーは端末のセキュア領域 (Keychain) に暗号化保存されます。")
                    }
                }
                
                // 3. データバックアップ & 復元 (NEW-07: インポート UI の追加)
                if let store = store {
                    Section {
                        Button(action: {
                            if let json = BackupService.exportBackupJSON(store: store) {
                                backupJSONText = json
                                #if canImport(UIKit)
                                UIPasteboard.general.string = json
                                #endif
                                feedbackMessage = "全データのJSONバックアップをクリップボードにコピーしました！"
                                isExportSheetPresented = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("JSON バックアップを出力・コピー")
                            }
                        }
                        
                        Button(action: {
                            isImportSheetPresented = true
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("JSON バックアップから復元 (インポート)")
                                    .foregroundColor(.orange)
                            }
                        }
                    } header: {
                        Text("データバックアップ & 復元")
                    } footer: {
                        if let msg = feedbackMessage {
                            Text(msg).foregroundColor(.blue)
                        } else {
                            Text("コースやカード、学習ログを含む全データをJSON形式でエクスポート・インポートできます。")
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
            .sheet(isPresented: $isExportSheetPresented) {
                NavigationStack {
                    ScrollView {
                        Text(backupJSONText)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                    }
                    .navigationTitle("JSON エクスポート")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { isExportSheetPresented = false }
                        }
                    }
                }
            }
            // NEW-07: JSON 復元（インポート）シート
            .sheet(isPresented: $isImportSheetPresented) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("復元する JSON バックアップデータを貼り付けてください:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            #if canImport(UIKit)
                            Button("📋 クリップボードから読み込み") {
                                if let str = UIPasteboard.general.string {
                                    restoreInputJSON = str
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            #endif
                        }
                        
                        TextEditor(text: $restoreInputJSON)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                            .frame(minHeight: 200)
                        
                        Button(action: executeRestore) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("このデータで復元を実行")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(restoreInputJSON.isEmpty ? Color.gray : Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(restoreInputJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("JSON 復元 (インポート)")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("キャンセル") { isImportSheetPresented = false }
                        }
                    }
                }
            }
            .onAppear {
                loadApiKey()
            }
        }
    }
    
    // NEW-06: APIキー操作関数
    private func loadApiKey() {
        if let key = KeychainStore.load(key: "openAIApiKey"), !key.isEmpty {
            apiKeyInput = key
            isApiKeySaved = true
        } else {
            isApiKeySaved = false
        }
    }
    
    private func saveApiKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if KeychainStore.save(key: "openAIApiKey", value: trimmed) {
            isApiKeySaved = true
            apiKeyFeedback = "APIキーをKeychainに保存しました！"
        }
    }
    
    private func deleteApiKey() {
        if KeychainStore.delete(key: "openAIApiKey") {
            apiKeyInput = ""
            isApiKeySaved = false
            apiKeyFeedback = "KeychainからAPIキーを削除しました。"
        }
    }
    
    // NEW-07: バックアップ復元実行関数
    private func executeRestore() {
        guard let store = store else { return }
        let success = BackupService.importBackupJSON(jsonString: restoreInputJSON, store: store)
        if success {
            feedbackMessage = "✅ データの復元（インポート）が正常に完了しました！"
            isImportSheetPresented = false
        } else {
            feedbackMessage = "❌ JSONフォーマットが無効です。正確なバックアップテキストを入力してください。"
        }
    }
}
