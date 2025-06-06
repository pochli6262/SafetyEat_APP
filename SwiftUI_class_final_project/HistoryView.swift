import SwiftUI
import MarkdownUI
import Foundation
import UIKit

// 分析紀錄資料模型（圖片存為檔案）
struct HistoryCard: Identifiable, Codable {
    let id: UUID
    let imageFilename: String // 空字串 = 無圖片
    let result: String
    let allergens: [String]

    var hasImage: Bool {
        !imageFilename.isEmpty
    }

    var image: UIImage? {
        guard hasImage else { return nil }
        let url = HistoryViewModel.documentsDirectory.appendingPathComponent(imageFilename)
        return UIImage(contentsOfFile: url.path)
    }
}


// 紀錄 ViewModel，儲存圖片與 JSON 檔案
class HistoryViewModel: ObservableObject {
    @Published var cards: [HistoryCard] = []
    
    private let storageFilename = "history_cards.json"
    
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private var storageURL: URL {
        Self.documentsDirectory.appendingPathComponent(storageFilename)
    }
    
    init() {
        load()
        
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path
        print("📁 Documents 路徑：\(path)")
    }
    
    func addCard(image: UIImage?, result: String, allergens: [String]) {
        let id = UUID()
        var filename = ""

        if let image = image {
            if let data = image.jpegData(compressionQuality: 0.7) {
                filename = "\(id.uuidString).jpg"
                let imageURL = Self.documentsDirectory.appendingPathComponent(filename)
                do {
                    try data.write(to: imageURL)
                    print("✅ 圖片寫入成功：\(filename)")
                } catch {
                    print("❌ 圖片寫入失敗：\(error.localizedDescription)")
                    filename = ""
                }
            } else {
                print("❌ 無法轉成 JPEG")
            }
        } else {
            print("⚠️ 傳入的 image 為 nil")
        }

        let newCard = HistoryCard(id: id, imageFilename: filename, result: result, allergens: allergens)
        cards.insert(newCard, at: 0)
        save()
    }

    
    func removeCard(_ card: HistoryCard) {
        cards.removeAll { $0.id == card.id }
        
        // 刪除圖片
        let imageURL = Self.documentsDirectory.appendingPathComponent(card.imageFilename)
        try? FileManager.default.removeItem(at: imageURL)
        
        save()
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(cards) {
            try? encoded.write(to: storageURL)
        }
    }
    
    func load() {
        if let data = try? Data(contentsOf: storageURL),
           let saved = try? JSONDecoder().decode([HistoryCard].self, from: data) {
            self.cards = saved
        }
    }
    
    func clear() {
        for card in cards {
            let imageURL = Self.documentsDirectory.appendingPathComponent(card.imageFilename)
            try? FileManager.default.removeItem(at: imageURL)
        }
        cards.removeAll()
        try? FileManager.default.removeItem(at: storageURL)
    }
}

// 顯示紀錄列表
struct HistoryView: View {
    @EnvironmentObject var historyVM: HistoryViewModel
    @State private var showClearAlert = false
    @State private var animateCards = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(historyVM.cards.enumerated()), id: \.element.id) { index, card in
                        NavigationLink(destination: HistoryDetailView(card: card)) {
                            HistoryCardRow(card: card)
                                .opacity(animateCards ? 1 : 0)
                                .offset(x: animateCards ? 0 : 100)
                                .animation(.easeOut(duration: 0.45).delay(Double(index) * 0.12), value: animateCards)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("分析紀錄")
            .toolbar {
                if !historyVM.cards.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("清空全部") {
                            showClearAlert = true
                        }
                    }
                }
            }
            .alert("確定要清空所有紀錄嗎？", isPresented: $showClearAlert) {
                Button("清空", role: .destructive) {
                    historyVM.clear()
                }
                Button("取消", role: .cancel) { }
            }
            .onAppear {
                animateCards = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    animateCards = true
                }
            }
        }
    }
}

struct HistoryCardRow: View {
    let card: HistoryCard

    var body: some View {
        HStack {
            if let img = card.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .clipped()
            } else {
                Image(systemName: "fork.knife.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.black)
                    .padding(10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("過敏原：\(card.allergens.joined(separator: "、"))")
                    .font(.subheadline)
                    .lineLimit(1)
                Text("點擊查看詳細分析")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .shadow(color: .gray.opacity(0.1), radius: 1, x: 0, y: 1)
    }
}


// 顯示單一紀錄詳細資訊
struct HistoryDetailView: View {
    @EnvironmentObject var historyVM: HistoryViewModel
    @Environment(\.dismiss) var dismiss
    
    let card: HistoryCard
    @State private var showDeleteAlert = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if card.hasImage, let img = card.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(10)
                }

                
                Text("過敏原：\(card.allergens.joined(separator: "、"))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Markdown(card.result)
                
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("刪除這筆紀錄")
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(10)
            }
            .padding()
        }
        .navigationTitle("詳細分析")
        .navigationBarTitleDisplayMode(.inline)
        .alert("確定要刪除此紀錄嗎？", isPresented: $showDeleteAlert) {
            Button("刪除", role: .destructive) {
                historyVM.removeCard(card)
                dismiss()
            }
            Button("取消", role: .cancel) { }
        }
    }
}
