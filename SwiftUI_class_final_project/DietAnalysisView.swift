import SwiftUI
import PhotosUI
import Charts
import MarkdownUI

struct DietAnalysisView: View {
    enum MealType: String, CaseIterable {
        case 早餐, 午餐, 晚餐
    }

    @State private var mealImages: [MealType: UIImage] = [:]
    @State private var mealNutrition: [MealType: NutritionInfo] = [:]
    @State private var isLoading: Bool = false
    @State private var analysisResult: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(MealType.allCases, id: \.self) { type in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(type.rawValue, systemImage: iconName(for: type))
                                    .font(.headline)
                                Spacer()
                            }

                            if let img = mealImages[type] {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 140)
                                    .cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2)))
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 140)
                                    .overlay(Text("尚未選擇圖片").foregroundColor(.gray))
                                    .cornerRadius(10)
                            }

                            PhotosPicker("選擇 \(type.rawValue) 圖片", selection: Binding(
                                get: { nil },
                                set: { newItem in
                                    Task {
                                        guard let item = newItem,
                                              let data = try? await item.loadTransferable(type: Data.self),
                                              let image = UIImage(data: data) else { return }

                                        mealImages[type] = image
                                        isLoading = true
                                        if let nutrition = await analyzeImage(image) {
                                            mealNutrition[type] = nutrition
                                        } else {
                                            errorMessage = "❌ \(type.rawValue) 無法解析"
                                        }
                                        isLoading = false
                                    }
                                }), matching: .images)
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
                    }
                    
                    if hasUploadedImages() {
                        Button("再試一次") {
                            Task {
                                isLoading = true
                                errorMessage = nil
                                for (type, image) in mealImages {
                                    if let nutrition = await analyzeImage(image) {
                                        mealNutrition[type] = nutrition
                                    } else {
                                        errorMessage = "❌ \(type.rawValue) 再試一次也失敗"
                                    }
                                }
                                isLoading = false
                            }
                        }
                        .buttonStyle(.bordered)
                    }


                    if isLoading {
                        ProgressView("分析中...").padding()
                    }

                    if !mealNutrition.isEmpty {
                        Text("📊 一日累積營養素")
                            .font(.title3.bold())
                            .padding(.top)

                        let nutritionOrder = ["熱量", "蛋白質", "脂肪", "碳水化合物", "糖", "鈉"]

                        Chart(groupedNutritionItems().sorted {
                            nutritionOrder.firstIndex(of: $0.name) ?? 0
                            < nutritionOrder.firstIndex(of: $1.name) ?? 0
                        }) { item in
                            BarMark(
                                x: .value("營養素", item.name),
                                y: .value("攝取量", item.value)
                            )
                            .foregroundStyle(by: .value("餐別", item.mealType.rawValue))
                        }
                        .frame(height: 300)
                        .padding(.horizontal)
                    }

                    Button("分析今日飲食是否健康") {
                        Task {
                            isLoading = true
                            analysisResult = ""
                            errorMessage = nil
                            let total = combinedNutritionDict()
                            analysisResult = await analyzeHealth(for: total)
                            isLoading = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)

                    if !analysisResult.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("🔍 AI 分析結果")
                                .font(.headline)

                            Markdown(analysisResult)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(10)
                        }
                    }


                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color(.systemRed).opacity(0.1))
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("🍱 飲食分析助手")
        }
    }
    
    func hasUploadedImages() -> Bool {
        !mealImages.isEmpty
    }


    func iconName(for type: MealType) -> String {
        switch type {
        case .早餐: return "sunrise"
        case .午餐: return "sun.max"
        case .晚餐: return "moon.stars"
        }
    }


    // 把每一餐轉換成帶有類別的營養項目
    func groupedNutritionItems() -> [ColoredNutritionItem] {
        var result: [ColoredNutritionItem] = []

        for (meal, info) in mealNutrition {
            for (k, v) in info.numericDict() {
                result.append(ColoredNutritionItem(mealType: meal, name: k, value: v))
            }
        }

        return result
    }

    func combinedNutritionDict() -> [String: Double] {
        var total: [String: Double] = [:]
        for (_, info) in mealNutrition {
            for (k, v) in info.numericDict() {
                total[k, default: 0] += v
            }
        }
        return total
    }

    func analyzeImage(_ image: UIImage) async -> NutritionInfo? {
        let resized = image.resized(toMaxSide:  200)
        guard let data = resized.jpegData(compressionQuality: 0.1) else { return nil }
        let base64 = data.base64EncodedString()

        let prompt = """
請從這張圖片中萃取出吃完全部份量的營養標示資訊，每個""中間只能放一個數值，格式如下，請直接回傳 JSON：

{
  "營養標示": {
    "熱量": "",
    "蛋白質": "",
    "脂肪": "",
    "碳水化合物": "",
    "糖": "",
    "鈉": ""
  }
}
"""

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": prompt],
                    ["inlineData": [
                        "mimeType": "image/jpeg",
                        "data": base64
                    ]]
                ]
            ]]
        ]

        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=AIzaSyBllZRcAOOLyfQpL_WdSIjrnoHw_WHH2uU")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let fullText = parts.first?["text"] as? String,
              let jsonString = extractJSONString(from: fullText),
              let jsonData = jsonString.data(using: .utf8),
              let result = try? JSONDecoder().decode([String: NutritionInfo].self, from: jsonData)
        else {
            return nil
        }
        print(fullText)

        return result["營養標示"]
    }

    func analyzeHealth(for nutrition: [String: Double]) async -> String {
        let formatted = nutrition.map { "\($0.key)：\($0.value)" }.joined(separator: "\n")

        let prompt = """
        以下是一整天的營養攝取量，請你扮演一位營養師，用繁體中文 **以 Markdown 格式回覆分析報告**，客觀分析一位身高體重皆為平均值的成年男性是否營養均衡，直接回答就好，若有攝取過多或不足的部分，請具體指出。

        建議每日營養標準可參考台灣衛福部。

        資料如下：

        \(formatted)
        """


        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [["text": prompt]]
            ]]
        ]

        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=AIzaSyBllZRcAOOLyfQpL_WdSIjrnoHw_WHH2uU")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let result = parts.first?["text"] as? String else {
            return "⚠️ 無法分析今日飲食"
        }

        return result
    }

    func extractJSONString(from text: String) -> String? {
        guard let start = text.range(of: "{"),
              let end = text.range(of: "}", options: .backwards) else {
            return nil
        }

        let substring = text[start.lowerBound...end.upperBound]

        // ✅ 嘗試 decode 確保是有效 JSON
        if let data = substring.data(using: .utf8),
           let _ = try? JSONSerialization.jsonObject(with: data) {
            return String(substring)
        }

        return nil
    }

}

struct ColoredNutritionItem: Identifiable {
    let id = UUID()
    let mealType: DietAnalysisView.MealType
    let name: String
    let value: Double
}

struct NutritionInfo: Codable {
    let 熱量: String?
    let 蛋白質: String?
    let 脂肪: String?
    let 碳水化合物: String?
    let 糖: String?
    let 鈉: String?

    func numericDict() -> [String: Double] {
        func extractNumber(_ text: String?) -> Double {
            guard let t = text else { return 0 }
            let cleaned = t.replacingOccurrences(of: "[^0-9\\.]", with: "", options: .regularExpression)
            return Double(cleaned) ?? 0
        }

        return [
            "熱量": extractNumber(熱量),
            "蛋白質": extractNumber(蛋白質),
            "脂肪": extractNumber(脂肪),
            "碳水化合物": extractNumber(碳水化合物),
            "糖": extractNumber(糖),
            "鈉": extractNumber(鈉)
        ]
    }

}


import UIKit

extension UIImage {
    func resized(toMaxSide maxSide: CGFloat) -> UIImage {
        let maxDimension = max(size.width, size.height)
        guard maxDimension > maxSide else { return self }

        let scale = maxSide / maxDimension
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

