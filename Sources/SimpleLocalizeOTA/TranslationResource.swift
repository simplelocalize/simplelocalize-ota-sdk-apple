import Foundation

/// A single downloadable file on Translation Hosting.
struct TranslationResource: Hashable {
  let language: String
  /// Empty string means the default resource (no namespace).
  let namespace: String
  let customerId: String?

  init(language: String, namespace: String = "", customerId: String? = nil) {
    self.language = language
    self.namespace = namespace
    self.customerId = customerId
  }

  /// Path relative to the CDN base URL, e.g. `TOKEN/_production/pl_PL/common`.
  func path(projectToken: String, environment: String) -> String {
    var languageComponent = language
    if let customerId, !customerId.isEmpty {
      languageComponent += "_" + customerId
    }
    var components = [projectToken, environment, languageComponent]
    if !namespace.isEmpty {
      components.append(namespace)
    }
    return components.joined(separator: "/")
  }

  func url(projectToken: String, environment: String, baseURL: URL) -> URL {
    var url = baseURL
    for component in path(projectToken: projectToken, environment: environment).split(separator: "/") {
      url.appendPathComponent(String(component))
    }
    return url
  }

  /// Stable, file system safe name used by the on-disk cache.
  var cacheFileName: String {
    var name = language
    if let customerId, !customerId.isEmpty {
      name += "_" + customerId
    }
    if !namespace.isEmpty {
      name += "." + namespace.replacingOccurrences(of: "/", with: "-")
    }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    let sanitized = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    return sanitized + ".json"
  }
}
