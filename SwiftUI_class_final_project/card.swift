import SwiftUI
import PhotosUI
import MarkdownUI

import Foundation
import UIKit

struct HistoryCard: Identifiable, Codable {
    let id: UUID
    let imageData: Data
    let result: String
    let allergens: [String]

    var image: UIImage? {
        UIImage(data: imageData)
    }

    init(image: UIImage, result: String, allergens: [String]) {
        self.id = UUID()
        self.imageData = image.jpegData(compressionQuality: 0.7) ?? Data()
        self.result = result
        self.allergens = allergens
    }
}


class HistoryViewModel: ObservableObject {
    @Published var cards: [HistoryCard] = []

    private let storageKey = "history_cards"

    init() {
        load()
    }

    func addCard(image: UIImage, result: String, allergens: [String]) {
        let newCard = HistoryCard(image: image, result: result, allergens: allergens)
        cards.insert(newCard, at: 0)
        save()
    }
    
    func removeCard(_ card: HistoryCard) {
        cards.removeAll { $0.id == card.id }
        save()
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([HistoryCard].self, from: data) {
            self.cards = saved
        }
    }

    func clear() {
        cards.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

struct HistoryView: View {
    @EnvironmentObject var historyVM: HistoryViewModel
    @State private var showClearAlert = false
    @State private var deleteIndex: Int? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(Array(historyVM.cards.enumerated()), id: \.element.id) { index, card in
                        HistoryCardView(card: card) {
                            deleteIndex = index
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("分析紀錄")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !historyVM.cards.isEmpty {
                        Button("清空全部") {
                            showClearAlert = true
                        }
                    }
                }
            }
            .alert("確定要刪除此紀錄嗎？", isPresented: Binding(
                get: { deleteIndex != nil },
                set: { if !$0 { deleteIndex = nil } }
            )) {
                Button("刪除", role: .destructive) {
                    if let index = deleteIndex {
                        historyVM.cards.remove(at: index)
                        historyVM.save()
                    }
                    deleteIndex = nil
                }
                Button("取消", role: .cancel) {
                    deleteIndex = nil
                }
            }
            .alert("確定要清空所有紀錄嗎？", isPresented: $showClearAlert) {
                Button("清空", role: .destructive) {
                    historyVM.clear()
                }
                Button("取消", role: .cancel) { }
            }
        }
    }
}

struct HistoryCardView: View {
    let card: HistoryCard
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let img = card.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .cornerRadius(10)
            }

            Text("過敏原：\(card.allergens.joined(separator: "、"))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Markdown(card.result)
                .padding(.top, 4)

            HStack {
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("刪除", systemImage: "trash")
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
