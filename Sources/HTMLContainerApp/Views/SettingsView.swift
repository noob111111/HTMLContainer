import SwiftUI

struct SettingsView: View {
    @AppStorage("htmlSelectionSetting") private var htmlSelectionSettingRaw: Int = AutoOpenSetting.auto.rawValue

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

                Section(header: Text("About")) {
                    Text("HTMLContainer").font(.headline)
                    Text("Uses WebKit on iOS to render imported HTML packages.")
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
