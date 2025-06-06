import SwiftUI

// App 主程式入口，初始化 ViewModel 並注入環境
@main
struct SafetyEatApp: App {
    @StateObject var historyVM = HistoryViewModel()

    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(historyVM)
        }
    }
}

// 啟動畫面：顯示 logo 和一句標語後跳轉進入主頁面
struct SplashView: View {
    @State private var isActive = false
    @State private var rotationAngle: Double = 0

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
                        .rotationEffect(.degrees(rotationAngle))
                }
                Text("每一口安心，從看懂配料表開始")
                    .font(.headline)
                    .bold()
                    .foregroundColor(.white)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.pink)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5)) {
                    rotationAngle = 360
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        isActive = true
                    }
                }
            }
        }
    }
}
