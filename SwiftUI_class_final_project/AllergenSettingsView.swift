import SwiftUI

// 使用者自訂或選擇過敏原
struct AllergenSettingsView: View {
    @Binding var selection: [String]
    let all: [String]
    let saveAction: () -> Void
    @State private var customAllergen: String = ""

    var body: some View {
        Form {
            Section(header: Text("選擇過敏原")) {
                ForEach(all, id: \.self) { item in
                    Toggle(item, isOn: Binding(
                        get: { selection.contains(item) },
                        set: { on in
                            if on {
                                selection.append(item)
                            } else {
                                selection.removeAll { $0 == item }
                            }
                            saveAction()
                        }
                    ))
                }
            }
            Section(header: Text("新增自訂過敏原")) {
                HStack {
                    TextField("例如：芝麻", text: $customAllergen)
                    Button("加入") {
                        let trimmed = customAllergen.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !selection.contains(trimmed) else { return }
                        selection.append(trimmed)
                        customAllergen = ""
                        saveAction()
                    }
                }
            }
        }
        .navigationTitle("過敏原設定")
    }
}
