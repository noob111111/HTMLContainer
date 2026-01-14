import SwiftUI

struct SettingsView: View {
    @AppStorage("autoOpenSetting") private var autoOpenSettingRaw: Int = AutoOpenSetting.always.rawValue

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Import behavior")) {
                    Picker("Auto-open imported folders", selection: $autoOpenSettingRaw) {
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
