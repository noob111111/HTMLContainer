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
}
