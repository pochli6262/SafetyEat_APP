import SwiftUI
import PhotosUI
import Charts
import MarkdownUI

struct DietAnalysisView: View {
    enum MealType: String, CaseIterable {
        case 早餐, 午餐, 晚餐
    }

    @AppStorage("gender") private var selectedGender: String = "男性"
    @AppStorage("activity") private var selectedActivityLevel: String = "中等"
    @AppStorage("height") private var heightText: String = ""
    @AppStorage("weight") private var weightText: String = ""

    
    @State private var mealImages: [MealType: UIImage] = [:]
    @State private var mealNutrition: [MealType: NutritionInfo] = [:]
    @State private var isLoading: Bool = false
    @State private var analysisResult: String = ""
    @State private var errorMessage: String?
    
    @State private var isAnalyzingHealth: Bool = false


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 圖片輸入區略
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
                        Text("📊 一日攝取量占建議攝取百分比")
                            .font(.title3.bold())

                        let nutritionOrder = ["熱量", "蛋白質", "脂肪", "碳水化合物", "糖", "鈉"]

                        if percentageNutritionItems().isEmpty {
                            Text("⚠️ 請輸入有效的身高與體重，並上傳至少一餐圖片")
                                .foregroundColor(.gray)
                        } else {
                            Chart(percentageNutritionItems().sorted {
                                nutritionOrder.firstIndex(of: $0.name) ?? 0 < nutritionOrder.firstIndex(of: $1.name) ?? 0
                            }) { item in

                                // 🔲 背景：建議攝取量的框（100% 高度）
                                RectangleMark(
                                    x: .value("營養素", item.name),
                                    yStart: .value("建議底部", 0),
                                    yEnd: .value("建議上限", 100)
                                )
                                .foregroundStyle(Color.gray.opacity(0.15))
                                .cornerRadius(4)

                                // 🟦 前景：實際攝取量（可超出 100%）
                                BarMark(
                                    x: .value("營養素", item.name),
                                    y: .value("攝取百分比", item.value)
                                )
                                .foregroundStyle(by: .value("餐別", item.mealType.rawValue))
                            }
                            .frame(height: 300)
                            .padding(.horizontal)


                        }
                    }

                    // 分析按鈕與結果區
                    Button("分析今日飲食是否健康") {
                        Task {
                            isAnalyzingHealth = true
                            analysisResult = ""
                            errorMessage = nil
                            let total = combinedNutritionDict()
                            analysisResult = await analyzeHealth(
                                for: total,
                                gender: selectedGender,
                                height: heightText,
                                weight: weightText
                            )
                            isAnalyzingHealth = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                    
                    if isAnalyzingHealth {
                        ProgressView("AI 分析中...")
                            .padding(.top)
                    }


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

    func percentageNutritionItems() -> [ColoredNutritionItem] {
        guard let height = Double(heightText),
              let weight = Double(weightText) else {
            return []
        }

        let recommended = calculateRecommendedIntake(
            gender: selectedGender,
            heightCM: height,
            weightKG: weight,
            activityLevel: activityFactor(for: selectedActivityLevel)
        )

        var result: [ColoredNutritionItem] = []
        for (meal, info) in mealNutrition {
            for (k, v) in info.numericDict() {
                if let base = recommended[k], base > 0 {
                    let percent = min((v / base) * 100, 200)
                    result.append(ColoredNutritionItem(mealType: meal, name: k, value: percent))
                }
            }
        }
        return result
    }

    func calculateRecommendedIntake(gender: String, heightCM: Double, weightKG: Double, activityLevel: Double) -> [String: Double] {
        let bmr: Double = gender == "男性" ?
            66 + 13.7 * weightKG + 5 * heightCM - 6.8 * 30 :
            655 + 9.6 * weightKG + 1.8 * heightCM - 4.7 * 30

        let tdee = bmr * activityLevel

        return [
            "熱量": tdee,
            "蛋白質": weightKG * 1.2,
            "脂肪": tdee * 0.25 / 9,
            "碳水化合物": tdee * 0.55 / 4,
            "糖": 50,
            "鈉": 2000
        ]
    }

    func activityFactor(for level: String) -> Double {
        switch level {
        case "久坐": return 1.2
        case "輕度": return 1.375
        case "中等": return 1.55
        case "激烈": return 1.725
        default: return 1.2
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
        let resized = image.resized(toMaxSide: 200)
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

        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=AIzaSyBllZRcAOOLyfQpL_WdSIjrnoHw_WHH2uU")!) // 換成你的 API Key
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

        return result["營養標示"]
    }

    func analyzeHealth(for nutrition: [String: Double], gender: String, height: String, weight: String) async -> String {
        let formatted = nutrition.map { "\($0.key)：\($0.value)" }.joined(separator: "\n")

        let prompt = """
以下是一整天的營養攝取量，請你扮演一位營養師，用繁體中文 **以 Markdown 格式回覆分析報告**，分析以下這位使用者的營養攝取是否均衡，若有攝取過多或不足，請具體指出。

使用者資料：
- 性別：\(gender)
- 身高：\(height) 公分
- 體重：\(weight) 公斤

每日建議攝取量可參考台灣衛福部標準。

營養攝取資料如下：

\(formatted)
"""

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [["text": prompt]]
            ]]
        ]

        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=AIzaSyBllZRcAOOLyfQpL_WdSIjrnoHw_WHH2uU")!) // 換成你的 API Key
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
