import Foundation

/// Configuration of the Translation Hosting (CDN) source used by the SDK.
///
/// Everything here is public information - the project token is meant to be shipped
/// inside client apps, exactly like it is on the web.
public struct SimpleLocalizeConfiguration {

  /// Default CDN of SimpleLocalize Translation Hosting.
  public static let defaultBaseURL = URL(string: "https://cdn.simplelocalize.io")!

  /// Project token from Settings -> Credentials.
  public var projectToken: String

  /// Hosting environment key, e.g. `_production`, `_latest` or a custom environment key.
  public var environment: String

  /// CDN base URL. Change it when translations are published to a custom hosting provider.
  public var baseURL: URL

  /// Namespaces to download. Empty means the default (no namespace) resource.
  /// A namespace maps to the `table` argument of `NSLocalizedString`.
  public var namespaces: [String]

  /// Forces a language key instead of resolving it from the device locale.
  public var language: String?

  /// Language used when a key is missing in the current language.
  public var fallbackLanguage: String?

  /// Customer identifier for customer specific translations (`{language}_{customerId}`).
  public var customerId: String?

  /// Minimum time between two automatic refreshes. Manual `refresh()` calls ignore it.
  public var minimumRefreshInterval: TimeInterval

  /// Refresh translations when the app returns to the foreground.
  public var refreshOnForeground: Bool

  /// Session used for CDN requests. Replace it in tests or to apply a custom `URLSessionConfiguration`.
  public var session: URLSession

  /// Optional log sink, called with human readable diagnostics.
  public var logHandler: ((String) -> Void)?

  public init(
    projectToken: String,
    environment: String = "_production",
    baseURL: URL = SimpleLocalizeConfiguration.defaultBaseURL,
    namespaces: [String] = [],
    language: String? = nil,
    fallbackLanguage: String? = nil,
    customerId: String? = nil,
    minimumRefreshInterval: TimeInterval = 600,
    refreshOnForeground: Bool = true,
    session: URLSession = .shared,
    logHandler: ((String) -> Void)? = nil
  ) {
    self.projectToken = projectToken
    self.environment = environment
    self.baseURL = baseURL
    self.namespaces = namespaces
    self.language = language
    self.fallbackLanguage = fallbackLanguage
    self.customerId = customerId
    self.minimumRefreshInterval = minimumRefreshInterval
    self.refreshOnForeground = refreshOnForeground
    self.session = session
    self.logHandler = logHandler
  }
}

public enum SimpleLocalizeError: Error, LocalizedError {
  case notStarted
  case invalidResponse
  case httpStatus(Int)
  case languageNotAvailable([String])

  public var errorDescription: String? {
    switch self {
    case .notStarted:
      return "SimpleLocalize.start(_:) was not called"
    case .invalidResponse:
      return "Unexpected response from Translation Hosting"
    case .httpStatus(let code):
      return "Translation Hosting responded with HTTP \(code)"
    case .languageNotAvailable(let candidates):
      return "None of the languages \(candidates.joined(separator: ", ")) is published"
    }
  }
}
