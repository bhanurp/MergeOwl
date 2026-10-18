enum SettingsPane: String, CaseIterable, Identifiable {
    case account = "Account"
    case appearance = "Appearance"
    case refresh = "Refresh"
    case notifications = "Notifications"
    case repositories = "Repositories"
    case savedViews = "Saved Views"
    case advanced = "Advanced"

    static let defaultPane: Self = .account

    var id: Self { self }

    var symbolName: String {
        switch self {
        case .account:
            "person.crop.circle"
        case .appearance:
            "rectangle.3.group"
        case .refresh:
            "arrow.clockwise"
        case .notifications:
            "bell"
        case .repositories:
            "folder"
        case .savedViews:
            "line.3.horizontal.decrease.circle"
        case .advanced:
            "slider.horizontal.3"
        }
    }
}
