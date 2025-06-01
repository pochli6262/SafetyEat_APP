import SwiftUI
import PhotosUI
import MarkdownUI

@main
struct SafetyEatApp: App {
    @StateObject var historyVM = HistoryViewModel()

    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(historyVM) // ✅ 注入
        }
    }
}

struct SplashView: View {
    @State private var isActive = false

    var body: some View {
        if isActive {
            MainEntryView()
        } else {
            VStack {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 200, height: 200)
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120)
                }
                Text("每一口安心，從看懂配料表開始")
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.white)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.pink)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { isActive = true }
                }
            }
        }
    }
}

struct MainEntryView: View {
    var body: some View {
        TabView {
            EntrySelectorView()
                .tabItem {
                    Label("分析", systemImage: "doc.text.magnifyingglass")
                }
            
            HistoryView()
                .tabItem {
                    Label("記錄", systemImage: "clock")
                }
        }
    }
}


struct EntrySelectorView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("安心吃SafetyEat")
                    .font(.title.bold())
                Text("選擇輸入方式")
                    .font(.headline)
                VStack(spacing: 16) {
                    NavigationLink {
                        ContentView(mode: .image)
                    } label: {
                        entryButtonContent(icon: "photo.on.rectangle", title: "相簿", description: "從相簿中選擇已有的食品配料表圖片")
                    }
                    NavigationLink {
                        ContentView(mode: .text)
                    } label: {
                        entryButtonContent(icon: "pencil", title: "文字", description: "手動輸入食品配料表文字")
                    }
                }
                .padding(.horizontal)
                Spacer()
            }
            .padding()
        }
    }

    func entryButton(icon: String, title: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            entryButtonContent(icon: icon, title: title, description: description)
        }
    }

    func entryButtonContent(icon: String, title: String, description: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .padding()
                .background(Color.pink)
                .clipShape(Circle())
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(description).font(.caption)
            }
            .foregroundColor(.primary)
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// 原本的 ContentView 被整合為分析頁面，支援初始化模式傳入
struct ContentView: View {
    enum InputMode {
        case image, text
    }

    @AppStorage("selectedAllergens") private var selectedAllergensData: String = ""
    @State private var allergensSelection: [String] = []
    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var inputText: String = ""
    @State private var resultText: String = ""
    @State private var isLoading = false
    @State private var imageReady = false
    @State private var retryCount = 0
    @State private var isError = false
    
    @EnvironmentObject var historyVM: HistoryViewModel


    let mode: InputMode
    let defaultAllergens = ["堅果", "牛奶", "蛋", "小麥", "大豆", "花生", "海鮮"]
    let apiKey = "AIzaSyBllZRcAOOLyfQpL_WdSIjrnoHw_WHH2uU"

    var allAllergens: [String] {
        defaultAllergens + allergensSelection.filter { !defaultAllergens.contains($0) }
    }

    var body: some View {
        Form {
            Section(header: Text("過敏原設定")) {
                NavigationLink("查看/修改過敏原", destination: AllergenSettingsView(selection: $allergensSelection, all: allAllergens, saveAction: saveAllergens))
                Text("已選：\(allergensSelection.joined(separator: ", "))")
                    .font(.footnote)
            }

            if mode == .image {
                Section {
                    PhotosPicker("選擇圖片", selection: $selectedItem, matching: .images)
                        .onChange(of: selectedItem) { newItem in
                            Task {
                                imageReady = false
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
                                    image = uiImage
                                    imageReady = true
                                }
                            }
                        }

                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                            .cornerRadius(10)
                    }
                }
            } else if mode == .text {
                Section {
                    TextField("請輸入食物成分文字描述...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                if isLoading {
                    analysisInProgressView
                } else {
                    Button(retryCount > 0 ? "再試一次" : "開始分析") {
                        resultText = ""
                        isError = false
                        isLoading = true
                        retryCount += 1
                        loadAllergens()
                        if mode == .image, let image = image {
                            sendToGemini(image: image)
                        } else if mode == .text {
                            sendToGemini(text: inputText)
                        }
                    }
                    .disabled((mode == .image && (!imageReady || image == nil)) || (mode == .text && inputText.isEmpty))
                }
            }


            if !resultText.isEmpty {
                Section(header: Text("AI 分析結果：")) {
                    ScrollView {
                        Markdown(resultText)
                            .padding()
                    }
                }
            }
        }
        .navigationTitle("分析輸入")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("返回") { }
            }
        }
        .onAppear(perform: loadAllergens)
    }

    func saveAllergens() {
        selectedAllergensData = allergensSelection.joined(separator: ",")
    }

    func loadAllergens() {
        allergensSelection = selectedAllergensData.split(separator: ",").map { String($0) }
    }

    func sendToGemini(image: UIImage) {
        guard let imageData = image.resized(toMaxLength: 512).jpegData(compressionQuality: 0.5) else { return }
        let base64 = imageData.base64EncodedString()
        let allergenList = allergensSelection.joined(separator: "、")

        let fullPrompt = """
你是食品分析師，請依下列規則分析圖片中的食品是否含有過敏原，並且說明：
使用者過敏原：\(allergenList.isEmpty ? "（無）" : allergenList)
請嚴格根據下列原則分析：
- 僅根據內容本身，禁止推測未提及資訊（例如交叉污染、加工程序）
- 明確含有過敏原 ➜ 🔴 不可食用
- 可能含有或模糊 ➜ 🟡 謹慎食用
- 未含任何相關詞彙 ➜ 🟢 可以吃
請使用 markdown 格式回答。
"""

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": fullPrompt],
                    ["inlineData": ["mimeType": "image/jpeg", "data": base64]]
                ]
            ]]
        ]
        sendRequest(body: body)
    }

    func sendToGemini(text: String) {
        let allergenList = allergensSelection.joined(separator: "、")
        let fullPrompt = """
你是食品分析師，請依下列規則分析內容是否含有過敏原：
使用者過敏原：\(allergenList.isEmpty ? "（無）" : allergenList)
分析內容如下：\(text)
請嚴格根據下列原則分析：
- 僅根據內容本身，禁止推測未提及資訊（例如交叉污染、加工程序）
- 明確含有過敏原 ➜ 🔴 不可食用
- 可能含有或模糊 ➜ 🟡 謹慎食用
- 未含任何相關詞彙 ➜ 🟢 可以吃
請使用 markdown 格式回答。
"""

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [["text": fullPrompt]]
            ]]
        ]
        sendRequest(body: body)
    }

    func sendRequest(body: [String: Any]) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent?key=\(apiKey)"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            self.resultText = "格式錯誤"
            self.isError = true
            self.isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                self.isLoading = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    self.resultText = "錯誤：\(error.localizedDescription)\n請點擊「再試一次」"
                    self.isError = true
                }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                DispatchQueue.main.async {
                    self.resultText = "無法解析回應\n請點擊「再試一次」"
                    self.isError = true
                }
                return
            }
            DispatchQueue.main.async {
                self.resultText = text
                self.isError = false
                // 小卡要用
                if let image = self.image {
                    self.historyVM.addCard(image: image, result: text, allergens: self.allergensSelection)
                }
            }
        }.resume()
    }
    
    @ViewBuilder
    var analysisInProgressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                .scaleEffect(1.5)

            Text("正在分析食品成分…")
                .font(.body)
                .foregroundColor(.gray)

            Rectangle()
                .fill(Color.orange)
                .frame(height: 2)
                .padding(.horizontal)

            Text("本分析結果僅供參考，不構成醫療建議。\n請遵從專業醫師或營養師指示。")
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }

}

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

extension UIImage {
    func resized(toMaxLength maxLength: CGFloat) -> UIImage {
        let originalWidth = size.width
        let originalHeight = size.height
        let maxOriginal = Swift.max(originalWidth, originalHeight)
        let scale = maxLength / maxOriginal
        let newSize = CGSize(width: originalWidth * scale, height: originalHeight * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
