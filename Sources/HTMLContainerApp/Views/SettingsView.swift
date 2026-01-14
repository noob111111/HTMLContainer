import SwiftUI

struct SettingsView: View {
    @AppStorage("htmlSelectionSetting") private var htmlSelectionSettingRaw: Int = AutoOpenSetting.auto.rawValue
    @AppStorage("closeButtonPosition") private var closeButtonPositionRaw: Int = CloseButtonPosition.topRight.rawValue

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("HTML file selection")) {
                    Picker("When opening a folder", selection: $htmlSelectionSettingRaw) {
                        ForEach(AutoOpenSetting.allCases) { s in
                            Text(s.description).tag(s.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section(header: Text("Close button position")) {
                    Picker("Position", selection: $closeButtonPositionRaw) {
                        ForEach(CloseButtonPosition.allCases) { p in
                            Text(p.description).tag(p.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
