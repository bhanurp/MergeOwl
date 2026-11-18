import Foundation

/// A canonical web origin. API paths are derived rather than entered by users.
struct GitHubServer: Codable, Equatable, Hashable, Sendable {
    let webURL: URL
    static let dotCom = try! GitHubServer("https://github.com")

    init(_ input: String) throws {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", parts.port.map({ (1...65535).contains($0) }) ?? true else {
            throw GitHubClientError.apiFailure("Enter the HTTPS address of your GitHub server, such as https://github.example.com, without an API path, login, query or fragment.")
        }
        parts.scheme = "https"
        parts.host = host.lowercased()
        parts.path = ""
        if parts.port == 443 { parts.port = nil }
        guard let url = parts.url else { throw GitHubClientError.invalidResponse }
        webURL = url
    }
    var isDotCom: Bool { webURL.absoluteString == "https://github.com" }
    var label: String { webURL.host! + (webURL.port.map { ":\($0)" } ?? "") }
    func restURL(_ path: String) -> URL {
        (isDotCom ? URL(string: "https://api.github.com")! : webURL.appendingPathComponent("api/v3"))
            .appendingPathComponent(path)
    }
    var graphQLURL: URL { isDotCom ? restURL("graphql") : webURL.appendingPathComponent("api/graphql") }
    var tokenURL: URL { webURL.appendingPathComponent("settings/tokens") }
    init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(webURL.absoluteString)
    }
}

/// Never forward an account token to a different origin or downgrade HTTPS.
final class GitHubRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    static func permits(original: URL, target: URL) -> Bool {
        original.scheme == target.scheme && original.host == target.host && original.port == target.port
            && target.user == nil && target.password == nil
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let target = request.url,
              Self.permits(original: original, target: target) else { completionHandler(nil); return }
        completionHandler(request)
    }
}
