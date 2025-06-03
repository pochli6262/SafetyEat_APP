import SwiftUI
import PhotosUI
import MarkdownUI

struct AnalysisView: View {
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
                imageInputSection
            } else {
                textInputSection
            }

            analysisButtonSection

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
                Button("返回") {}
            }
        }
        .onAppear(perform: loadAllergens)
        .id(retryCount)
    }

    var imageInputSection: some View {
        Section {
            PhotosPicker("選擇圖片", selection: $selectedItem, matching: .images)
                .onChange(of: selectedItem) { _, newItem in
                    Task {
                        imageReady = false
                        guard let item = newItem, let data = try? await item.loadTransferable(type: Data.self),
                              let uiImage = UIImage(data: data) else {
                            return
                        }
                        let resized = uiImage.resized(toMaxLength: 256)
                        guard let compressed = resized.jpegData(compressionQuality: 0.2), compressed.count < 1_000_000 else {
                            return
                        }
                        image = resized
                        imageReady = true
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
    }

    var textInputSection: some View {
        Section {
            TextField("請輸入食物成分文字描述...", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
    }

    var analysisButtonSection: some View {
        Section {
            if isLoading {
                analysisInProgressView
            } else {
                Button(retryCount > 0 ? "再試一次" : "開始分析") {
                    startAnalysis()
                }
                .disabled((mode == .image && (!imageReady || image == nil)) || (mode == .text && inputText.isEmpty))
            }
        }
    }

    func saveAllergens() {
        selectedAllergensData = allergensSelection.joined(separator: ",")
    }

    func loadAllergens() {
        allergensSelection = selectedAllergensData.split(separator: ",").map { String($0) }
    }

    func startAnalysis() {
        resultText = ""
        isError = false
        isLoading = true
        retryCount += 1
        loadAllergens()

        if mode == .image, let image = image {
            GeminiService.analyze(image: image, allergens: allergensSelection) { result in
                handleGeminiResult(result, image: image)
            }
        } else if mode == .text {
            GeminiService.analyze(text: inputText, allergens: allergensSelection) { result in
                handleGeminiResult(result, image: nil)
            }
        }
    }

    func handleGeminiResult(_ result: Result<String, Error>, image: UIImage?) {
        DispatchQueue.main.async {
            isLoading = false
            switch result {
            case .success(let text):
                resultText = text
                isError = false
                historyVM.addCard(image: image, result: text, allergens: allergensSelection)
            case .failure(let error):
                resultText = "錯誤：\(error.localizedDescription)\n請點擊「再試一次」"
                isError = true
            }
        }
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

import UIKit

class GeminiService {
    static let apiKey = "AIzaSyBllZRcAOOLyfQpL_WdSIjrnoHw_WHH2uU"

    static func analyze(image: UIImage, allergens: [String], completion: @escaping (Result<String, Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.2),
              imageData.count < 1_000_000 else {
            completion(.failure(NSError(domain: "ImageTooLarge", code: 1, userInfo: nil)))
            return
        }

        let base64 = imageData.base64EncodedString()
        let prompt = promptText(for: allergens)

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": prompt],
                    ["inlineData": ["mimeType": "image/jpeg", "data": base64]]
                ]
            ]]
        ]

        send(body: body, completion: completion)
    }

    static func analyze(text: String, allergens: [String], completion: @escaping (Result<String, Error>) -> Void) {
        let allergenList = allergens.joined(separator: "、")
        let prompt = """
你是食品分析師，請依下列規則分析內容是否含有過敏原：
使用者過敏原：\(allergenList.isEmpty ? "（無）" : allergenList)
分析內容如下：\(text)

輸出時，先列出品名。
請嚴格根據下列原則分析：
- 僅根據內容本身，禁止推測未提及資訊（例如交叉污染、加工程序）
- 明確含有過敏原 ➜ 🔴 不可食用
- 可能含有或模糊 ➜ 🟡 謹慎食用
- 未含任何相關詞彙 ➜ 🟢 可以吃

請根據內容判斷食品是否含有以下營養成分，若有，請提供其大致含量（如有標示）：熱量、蛋白質、脂肪、碳水化合物、糖、鈉。

並最後綜合來說，這個食品能不能吃。

請使用乾淨的 markdown 格式回覆，規則如下：

- 主要標題使用 `#`，例如 `# 食品分析報告`
- 子標題使用 `##`，例如 `## 過敏原分析`、`## 營養標示`
- 加粗文字請使用 `**粗體**`，避免多餘符號或空格
- 每個段落之間請加一行空白（markdown 段落分隔）
- 列表請用 `-` 起頭，不要使用 `•` 或其他符號
"""

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [["text": prompt]]
            ]]
        ]

        send(body: body, completion: completion)
    }

    private static func promptText(for allergens: [String]) -> String {
        let allergenList = allergens.joined(separator: "、")
        return """
你是食品分析師，請依下列規則分析圖片中的食品是否含有過敏原，並且說明：
使用者過敏原：\(allergenList.isEmpty ? "（無）" : allergenList)

輸出時，先列出品名。
請嚴格根據下列原則分析：
- 僅根據內容本身，禁止推測未提及資訊（例如交叉污染、加工程序）
- 明確含有過敏原 ➜ 🔴 不可食用
- 可能含有或模糊 ➜ 🟡 謹慎食用
- 未含任何相關詞彙 ➜ 🟢 可以吃

請根據內容判斷食品是否含有以下營養成分，若有，請提供其大致含量（如有標示）：熱量、蛋白質、脂肪、碳水化合物、糖、鈉。

並最後綜合來說，這個食品能不能吃。

請使用乾淨的 markdown 格式回覆，規則如下：

- 主要標題使用 `#`，例如 `# 食品分析報告`
- 子標題使用 `##`，例如 `## 過敏原分析`、`## 營養標示`
- 加粗文字請使用 `**粗體**`，避免多餘符號或空格
- 每個段落之間請加一行空白（markdown 段落分隔）
- 列表請用 `-` 起頭，不要使用 `•` 或其他符號
"""
    }

    private static func send(body: [String: Any], completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent?key=\(apiKey)"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(NSError(domain: "InvalidRequest", code: 0)))
            return
        }
        
        print("📦 發送請求 JSON 大小：\(jsonData.count / 1024) KB")


        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10

        let session = URLSession(configuration: config)
        session.dataTask(with: request) { data, _, error in

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                completion(.failure(NSError(domain: "InvalidResponse", code: 2)))
                return
            }

            completion(.success(text))
        }.resume()
    }
}
