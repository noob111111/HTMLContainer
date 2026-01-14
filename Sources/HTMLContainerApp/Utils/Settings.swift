import Foundation

enum AutoOpenSetting: Int, CaseIterable, Identifiable {
    case auto = 0
    case askFirstTime = 1
    case alwaysAsk = 2

    var id: Int { rawValue }

    var description: String {
        switch self {
        case .auto: return "Automatically open HTML (index.html or first file)"
        case .askFirstTime: return "Ask which HTML to open on first tap"
        case .alwaysAsk: return "Always ask which HTML to open"
        }
    }
}

enum CloseButtonPosition: Int, CaseIterable, Identifiable {
    case topLeft = 0
    case topRight = 1
    case bottomLeft = 2
    case bottomRight = 3

    var id: Int { rawValue }

    var description: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
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
