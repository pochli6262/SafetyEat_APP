import SwiftUI

// 主畫面，包含兩個 tab：分析、紀錄
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

// 讓使用者選擇使用文字或圖片進行分析
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
                        AnalysisView(mode: .image)
                    } label: {
                        entryButtonContent(icon: "photo.on.rectangle", title: "相簿", description: "從相簿中選擇已有的食品配料表圖片")
                    }
                    NavigationLink {
                        AnalysisView(mode: .text)
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
