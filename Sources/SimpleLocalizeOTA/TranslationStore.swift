import Foundation

/// Thread safe in-memory storage of downloaded translations.
///
/// Lookups happen on the main thread during rendering, so they must be synchronous
/// and cheap - hence a plain lock instead of an actor.
final class TranslationStore {

  private let lock = NSLock()
  private var tables: [String: [String: [String: String]]] = [:]
  private var revisionValue: Int = 0

  var revision: Int {
    lock.lock()
    defer { lock.unlock() }
    return revisionValue
  }

  /// Replaces the content of one resource. Returns `true` when anything actually changed.
  @discardableResult
  func replace(language: String, namespace: String, translations: [String: String]) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if tables[language]?[namespace] == translations {
      return false
    }
    tables[language, default: [:]][namespace] = translations
    revisionValue += 1
    return true
  }

  func lookup(key: String, namespace: String, languages: [String]) -> String? {
    lock.lock()
    defer { lock.unlock() }
    for language in languages {
      if let value = tables[language]?[namespace]?[key], !value.isEmpty {
        return value
      }
    }
    return nil
  }

  func translations(language: String, namespace: String = "") -> [String: String] {
    lock.lock()
    defer { lock.unlock() }
    return tables[language]?[namespace] ?? [:]
  }

  func removeAll() {
    lock.lock()
    defer { lock.unlock() }
    tables.removeAll()
    revisionValue += 1
  }
}
