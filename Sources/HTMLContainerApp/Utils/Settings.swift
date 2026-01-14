import Foundation

enum AutoOpenSetting: Int, CaseIterable, Identifiable {
    case always = 0
    case askEveryTime = 1
    case askFirstTime = 2

    var id: Int { rawValue }

    var description: String {
        switch self {
        case .always: return "Always open imported folder automatically"
        case .askEveryTime: return "Ask every time whether to open after import"
        case .askFirstTime: return "Ask only the first time a folder is added"
        }
    }
}

struct SettingsStore {
    private static let askedKey = "askedFolders"
    private static let filePrefsKey = "filePreferences"

    static func hasAsked(forFolderPath path: String) -> Bool {
        let set = UserDefaults.standard.stringArray(forKey: askedKey) ?? []
        return set.contains(path)
    }

    static func markAsked(forFolderPath path: String) {
        var set = UserDefaults.standard.stringArray(forKey: askedKey) ?? []
        if !set.contains(path) {
            set.append(path)
            UserDefaults.standard.set(set, forKey: askedKey)
        }
    }

    // Save preferred HTML file for a folder
    static func setPreferredFile(_ filePath: String, forFolder folderPath: String) {
        var prefs = UserDefaults.standard.dictionary(forKey: filePrefsKey) as? [String: String] ?? [:]
        prefs[folderPath] = filePath
        UserDefaults.standard.set(prefs, forKey: filePrefsKey)
    }

    // Get preferred HTML file for a folder (returns nil if not set)
    static func preferredFile(forFolder folderPath: String) -> String? {
        let prefs = UserDefaults.standard.dictionary(forKey: filePrefsKey) as? [String: String] ?? [:]
        return prefs[folderPath]
    }
}
