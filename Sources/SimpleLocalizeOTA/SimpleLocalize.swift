import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Over-the-air translations for Apple platforms, backed by SimpleLocalize Translation Hosting.
///
/// ```swift
/// SimpleLocalize.shared.start(.init(projectToken: "5a5b...", environment: "_production"))
/// label.text = SLLocalizedString("home.title")
/// ```
public final class SimpleLocalize {

  /// Posted on the main thread whenever translations in memory changed.
  public static let translationsDidChangeNotification = Notification.Name("io.simplelocalize.ota.translationsDidChange")

  public static let shared = SimpleLocalize()

  private let lock = NSLock()
  private let refreshQueue = DispatchQueue(label: "io.simplelocalize.ota.refresh", qos: .utility)

  private var configuration: SimpleLocalizeConfiguration?
  private var cache: TranslationCache?
  private var loader: TranslationLoader?
  private let store = TranslationStore()
  private var resolvedLanguage: String?
  private var lastRefreshDate: Date?
  private var foregroundObserver: NSObjectProtocol?

  public init() {}

  // MARK: - Lifecycle

  /// Loads cached translations synchronously and starts a background refresh.
  /// Safe to call from `application(_:didFinishLaunchingWithOptions:)`.
  public func start(_ configuration: SimpleLocalizeConfiguration, cacheDirectory: URL? = nil) {
    let directory = cacheDirectory ?? TranslationCache.defaultDirectory(
      projectToken: configuration.projectToken,
      environment: configuration.environment
    )

    lock.lock()
    self.configuration = configuration
    self.cache = TranslationCache(directory: directory)
    self.loader = TranslationLoader(session: configuration.session)
    self.resolvedLanguage = configuration.language ?? Self.persistedLanguage(for: configuration)
    self.lastRefreshDate = nil
    lock.unlock()

    loadFromCache()
    observeForegroundIfNeeded()
    refresh()
  }

  /// Stops observing app lifecycle notifications and forgets the configuration.
  public func stop() {
    if let foregroundObserver {
      NotificationCenter.default.removeObserver(foregroundObserver)
    }
    lock.lock()
    foregroundObserver = nil
    configuration = nil
    cache = nil
    loader = nil
    resolvedLanguage = nil
    lock.unlock()
    store.removeAll()
  }

  /// Removes downloaded translations from memory and disk.
  public func clearCache() {
    let cache = withLock { self.cache }
    cache?.clear()
    store.removeAll()
  }

  // MARK: - State

  public var isStarted: Bool { withLock { configuration != nil } }

  /// Language key currently served, e.g. `pl_PL`. `nil` until the first successful download.
  public var currentLanguage: String? { withLock { resolvedLanguage } }

  /// Increases every time the in-memory translations change. Useful as a SwiftUI view identity.
  public var revision: Int { store.revision }

  /// Overrides the language at runtime, keeps it across launches and refreshes in the background.
  public func setLanguage(_ language: String?, completion: ((Result<Void, Error>) -> Void)? = nil) {
    let configuration = withLock { self.configuration }
    guard let configuration else {
      completion?(.failure(SimpleLocalizeError.notStarted))
      return
    }
    withLock {
      self.resolvedLanguage = language
      self.lastRefreshDate = nil
    }
    Self.persistLanguage(language, for: configuration)
    loadFromCache()
    notifyChange()
    refresh(completion: completion)
  }

  // MARK: - Lookup

  /// Returns the over-the-air translation, or `nil` when the key was not downloaded.
  public func otaString(forKey key: String, table: String? = nil) -> String? {
    let (namespaces, languages) = withLock { () -> ([String], [String]) in
      guard let configuration else { return ([], []) }
      var languages: [String] = []
      if let resolvedLanguage { languages.append(resolvedLanguage) }
      if let fallback = configuration.fallbackLanguage, !languages.contains(fallback) {
        languages.append(fallback)
      }
      return (self.searchNamespaces(for: table, configuration: configuration), languages)
    }
    guard !languages.isEmpty else { return nil }
    for namespace in namespaces {
      if let value = store.lookup(key: key, namespace: namespace, languages: languages) {
        return value
      }
    }
    return nil
  }

  /// Over-the-air translation with a fallback to the strings bundled in the app.
  public func string(_ key: String, table: String? = nil, defaultValue: String? = nil) -> String {
    if let value = otaString(forKey: key, table: table) {
      return value
    }
    return Bundle.main.localizedString(forKey: key, value: defaultValue, table: table)
  }

  /// All downloaded translations for the current language and the given namespace.
  public func allTranslations(namespace: String = "") -> [String: String] {
    guard let language = currentLanguage else { return [:] }
    return store.translations(language: language, namespace: namespace)
  }

  // MARK: - Refresh

  /// Downloads translations. Conditional requests make an unchanged refresh nearly free.
  /// - Parameter force: when `false`, respects `minimumRefreshInterval`.
  public func refresh(force: Bool = true, completion: ((Result<Void, Error>) -> Void)? = nil) {
    let snapshot = withLock { (configuration, cache, loader, resolvedLanguage, lastRefreshDate) }
    guard let configuration = snapshot.0, let cache = snapshot.1, let loader = snapshot.2 else {
      completion?(.failure(SimpleLocalizeError.notStarted))
      return
    }
    if !force, let last = snapshot.4, Date().timeIntervalSince(last) < configuration.minimumRefreshInterval {
      completion?(.success(()))
      return
    }

    refreshQueue.async { [weak self] in
      guard let self else { return }
      let result = self.performRefresh(
        configuration: configuration,
        cache: cache,
        loader: loader,
        knownLanguage: snapshot.3
      )
      DispatchQueue.main.async { completion?(result) }
    }
  }

  private func performRefresh(
    configuration: SimpleLocalizeConfiguration,
    cache: TranslationCache,
    loader: TranslationLoader,
    knownLanguage: String?
  ) -> Result<Void, Error> {
    let namespaces = configuration.namespaces.isEmpty ? [""] : configuration.namespaces
    var language = knownLanguage
    var changed = false
    var loadedAnyResource = false
    var sawNotFound = false

    if language == nil {
      let candidates = LanguageResolver.candidates(explicit: configuration.language)
      configuration.logHandler?("Resolving language, candidates: \(candidates.joined(separator: ", "))")
      for candidate in candidates {
        let resource = TranslationResource(
          language: candidate,
          namespace: namespaces[0],
          customerId: configuration.customerId
        )
        switch download(resource, configuration: configuration, cache: cache, loader: loader) {
        case .success(let didChange):
          language = candidate
          changed = changed || didChange
          loadedAnyResource = true
        case .failure(SimpleLocalizeError.httpStatus(404)):
          sawNotFound = true
          continue
        case .failure(let error):
          return .failure(error)
        }
        if language != nil { break }
      }
      guard let language else {
        return .failure(SimpleLocalizeError.languageNotAvailable(candidates))
      }
      withLock { self.resolvedLanguage = language }
      Self.persistLanguage(language, for: configuration)
      loadFromCache()
    }

    guard let currentLanguage = language else {
      return .failure(SimpleLocalizeError.notStarted)
    }

    var languages = [currentLanguage]
    if let fallback = configuration.fallbackLanguage, !languages.contains(fallback) {
      languages.append(fallback)
    }

    var firstError: Error?
    for language in languages {
      for namespace in namespaces {
        let resource = TranslationResource(
          language: language,
          namespace: namespace,
          customerId: configuration.customerId
        )
        if language == currentLanguage, namespace == namespaces[0], knownLanguage == nil {
          continue // already downloaded while resolving the language
        }
        switch download(resource, configuration: configuration, cache: cache, loader: loader) {
        case .success(let didChange):
          changed = changed || didChange
          loadedAnyResource = true
        case .failure(SimpleLocalizeError.httpStatus(404)):
          sawNotFound = true
          configuration.logHandler?("Resource not published: \(resource.path(projectToken: configuration.projectToken, environment: configuration.environment))")
        case .failure(let error):
          firstError = firstError ?? error
        }
      }
    }

    if changed {
      notifyChange()
    }
    if let firstError {
      return .failure(firstError)
    }
    // Nothing at all is published for this language - do not pretend the refresh succeeded.
    if !loadedAnyResource && sawNotFound {
      withLock { self.resolvedLanguage = nil }
      return .failure(SimpleLocalizeError.languageNotAvailable(languages))
    }
    withLock { self.lastRefreshDate = Date() }
    return .success(())
  }

  /// Downloads one resource synchronously. Returns whether the in-memory content changed.
  private func download(
    _ resource: TranslationResource,
    configuration: SimpleLocalizeConfiguration,
    cache: TranslationCache,
    loader: TranslationLoader
  ) -> Result<Bool, Error> {
    let url = resource.url(
      projectToken: configuration.projectToken,
      environment: configuration.environment,
      baseURL: configuration.baseURL
    )
    let cached = cache.read(resource)
    let semaphore = DispatchSemaphore(value: 0)
    var outcome: Result<TranslationLoader.Outcome, Error> = .failure(SimpleLocalizeError.invalidResponse)
    loader.load(url: url, etag: cached?.etag) { result in
      outcome = result
      semaphore.signal()
    }
    semaphore.wait()

    switch outcome {
    case .failure(let error):
      configuration.logHandler?("Download failed for \(url.absoluteString): \(error.localizedDescription)")
      return .failure(error)
    case .success(.notFound):
      return .failure(SimpleLocalizeError.httpStatus(404))
    case .success(.notModified):
      configuration.logHandler?("Not modified: \(url.absoluteString)")
      if let cached {
        let changed = store.replace(language: resource.language, namespace: resource.namespace, translations: cached.translations)
        return .success(changed)
      }
      return .success(false)
    case .success(.updated(let translations, let etag)):
      configuration.logHandler?("Downloaded \(translations.count) keys from \(url.absoluteString)")
      let changed = store.replace(language: resource.language, namespace: resource.namespace, translations: translations)
      try? cache.write(.init(etag: etag, updatedAt: Date(), translations: translations), for: resource)
      return .success(changed)
    }
  }

  // MARK: - Cache

  private func loadFromCache() {
    let snapshot = withLock { (configuration, cache, resolvedLanguage) }
    guard let configuration = snapshot.0, let cache = snapshot.1, let language = snapshot.2 else { return }
    var languages = [language]
    if let fallback = configuration.fallbackLanguage, !languages.contains(fallback) {
      languages.append(fallback)
    }
    let namespaces = configuration.namespaces.isEmpty ? [""] : configuration.namespaces
    var changed = false
    for language in languages {
      for namespace in namespaces {
        let resource = TranslationResource(language: language, namespace: namespace, customerId: configuration.customerId)
        if let entry = cache.read(resource) {
          changed = store.replace(language: language, namespace: namespace, translations: entry.translations) || changed
        }
      }
    }
    if changed {
      notifyChange()
    }
  }

  // MARK: - Helpers

  private func searchNamespaces(for table: String?, configuration: SimpleLocalizeConfiguration) -> [String] {
    let requested: String
    if let table, !table.isEmpty, table != "Localizable" {
      requested = table
    } else {
      requested = configuration.namespaces.isEmpty ? "" : configuration.namespaces[0]
    }
    var namespaces = [requested]
    for namespace in configuration.namespaces where !namespaces.contains(namespace) {
      namespaces.append(namespace)
    }
    return namespaces
  }

  private func observeForegroundIfNeeded() {
    #if canImport(UIKit) && !os(watchOS)
    let refreshOnForeground = withLock { configuration?.refreshOnForeground ?? false }
    guard refreshOnForeground, withLock({ foregroundObserver }) == nil else { return }
    let observer = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.refresh(force: false)
    }
    withLock { foregroundObserver = observer }
    #endif
  }

  private func notifyChange() {
    let name = Self.translationsDidChangeNotification
    if Thread.isMainThread {
      NotificationCenter.default.post(name: name, object: self)
    } else {
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: name, object: self)
      }
    }
  }

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private static func languageDefaultsKey(for configuration: SimpleLocalizeConfiguration) -> String {
    "io.simplelocalize.ota.language.\(configuration.projectToken).\(configuration.environment)"
  }

  private static func persistedLanguage(for configuration: SimpleLocalizeConfiguration) -> String? {
    UserDefaults.standard.string(forKey: languageDefaultsKey(for: configuration))
  }

  private static func persistLanguage(_ language: String?, for configuration: SimpleLocalizeConfiguration) {
    let key = languageDefaultsKey(for: configuration)
    if let language {
      UserDefaults.standard.set(language, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
}

/// Drop-in replacement for `NSLocalizedString` that prefers over-the-air content.
public func SLLocalizedString(
  _ key: String,
  table: String? = nil,
  defaultValue: String? = nil,
  comment: String = ""
) -> String {
  SimpleLocalize.shared.string(key, table: table, defaultValue: defaultValue)
}

public extension String {
  /// `"home.title".simpleLocalized` - over-the-air translation with a bundle fallback.
  var simpleLocalized: String {
    SimpleLocalize.shared.string(self)
  }

  func simpleLocalized(table: String? = nil, arguments: CVarArg...) -> String {
    let format = SimpleLocalize.shared.string(self, table: table)
    if arguments.isEmpty { return format }
    return String(format: format, arguments: arguments)
  }
}
