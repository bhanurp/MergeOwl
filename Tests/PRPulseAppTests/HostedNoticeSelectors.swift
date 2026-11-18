import Foundation

// Shared by the native runner and unit tests; never compiled into the app.
enum HostedNoticeSelectors {
    // Native macOS static text uses AXValue; button captions use AXTitle.
    // AXDescription (XCTest's label) can be empty for both.
    static var pythonNotice: NSPredicate {
        NSPredicate(format: "value CONTAINS %@ AND value CONTAINS %@ AND value CONTAINS %@", "Python", "find devices", "local networks")
    }
    static var deny: NSPredicate {
        NSPredicate(format: "title IN %@", ["Don't Allow", "Don’t Allow"])
    }
}
