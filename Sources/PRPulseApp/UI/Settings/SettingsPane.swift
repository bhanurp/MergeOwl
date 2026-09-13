enum SettingsPane: String, CaseIterable, Identifiable {
    case account = "Account"
    case refresh = "Refresh"
    case notifications = "Notifications"
    case repositories = "Repositories"
    case advanced = "Advanced"

    static let defaultPane: Self = .account

    var id: Self { self }

    var symbolName: String {
        switch self {
        case .account:
            "person.crop.circle"
        case .refresh:
            "arrow.clockwise"
        case .notifications:
            "bell"
        case .repositories:
            "folder"
        case .advanced:
            "slider.horizontal.3"
        }
    }
}
