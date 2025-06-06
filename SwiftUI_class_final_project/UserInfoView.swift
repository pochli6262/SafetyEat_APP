import SwiftUI

struct UserInfoView: View {
    @AppStorage("gender") var gender: String = "男性"
    @AppStorage("activity") var activity: String = "中等"
    @AppStorage("height") var height: String = ""
    @AppStorage("weight") var weight: String = ""

    let activityLevels = ["久坐", "輕度", "中等", "激烈"]

    var body: some View {
        Form {
            Section(header: Text("性別")) {
                Picker("性別", selection: $gender) {
                    Text("男性").tag("男性")
                    Text("女性").tag("女性")
                }.pickerStyle(.segmented)
            }

            Section(header: Text("活動量")) {
                Picker("活動量", selection: $activity) {
                    ForEach(activityLevels, id: \.self) { level in
                        Text(level)
                    }
                }.pickerStyle(.segmented)
            }

            Section(header: Text("身高／體重")) {
                TextField("身高（cm）", text: $height)
                    .keyboardType(.decimalPad)
                TextField("體重（kg）", text: $weight)
                    .keyboardType(.decimalPad)
            }
        }
        .navigationTitle("使用者資訊")
    }
}
