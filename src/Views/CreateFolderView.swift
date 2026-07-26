import SwiftUI

/// 新規フォルダ作成シート
@available(iOS 17.0, macOS 14.0, *)
public struct CreateFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedIcon: String = "folder.fill"
    
    public let onCreate: (CourseFolder) -> Void
    
    private let availableIcons = [
        "folder.fill", "book.fill", "graduationcap.fill",
        "globe.americas.fill", "cpu.fill", "star.fill",
        "briefcase.fill", "lightbulb.fill"
    ]
    
    public init(onCreate: @escaping (CourseFolder) -> Void) {
        self.onCreate = onCreate
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("フォルダ名") {
                    TextField("例: 語学学習、資格試験など", text: $name)
                }
                
                Section("アイコン") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title3)
                                .foregroundColor(selectedIcon == icon ? .white : .blue)
                                .frame(width: 44, height: 44)
                                .background(selectedIcon == icon ? Color.blue : Color.blue.opacity(0.1))
                                .cornerRadius(10)
                                .onTapGesture {
                                    selectedIcon = icon
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("フォルダを作成")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let newFolder = CourseFolder(name: trimmed, iconName: selectedIcon)
                        onCreate(newFolder)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
