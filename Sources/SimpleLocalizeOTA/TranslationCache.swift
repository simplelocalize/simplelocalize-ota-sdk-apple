import Foundation

/// Persists downloaded resources so the app starts with the last known translations,
/// even offline, and so refreshes can be revalidated with `If-None-Match`.
final class TranslationCache {

  struct Entry: Codable {
    var etag: String?
    var updatedAt: Date
    var translations: [String: String]
  }

  private let directory: URL
  private let fileManager: FileManager
  private let lock = NSLock()

  init(directory: URL, fileManager: FileManager = .default) {
    self.directory = directory
    self.fileManager = fileManager
  }

  /// Default location: Application Support/SimpleLocalizeOTA/<token>/<environment>.
  static func defaultDirectory(projectToken: String, environment: String, fileManager: FileManager = .default) -> URL {
    let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return base
      .appendingPathComponent("SimpleLocalizeOTA", isDirectory: true)
      .appendingPathComponent(projectToken, isDirectory: true)
      .appendingPathComponent(environment, isDirectory: true)
  }

  func read(_ resource: TranslationResource) -> Entry? {
    lock.lock()
    defer { lock.unlock() }
    let url = directory.appendingPathComponent(resource.cacheFileName)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder.simpleLocalize.decode(Entry.self, from: data)
  }

  func write(_ entry: Entry, for resource: TranslationResource) throws {
    lock.lock()
    defer { lock.unlock() }
    try createDirectoryIfNeeded()
    let url = directory.appendingPathComponent(resource.cacheFileName)
    let data = try JSONEncoder.simpleLocalize.encode(entry)
    try data.write(to: url, options: .atomic)
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    try? fileManager.removeItem(at: directory)
  }

  private func createDirectoryIfNeeded() throws {
    guard !fileManager.fileExists(atPath: directory.path) else { return }
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    var mutable = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? mutable.setResourceValues(values)
  }
}

extension JSONDecoder {
  static var simpleLocalize: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return decoder
  }
}

extension JSONEncoder {
  static var simpleLocalize: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    return encoder
  }
}
