import Foundation

/// Maps device locales to SimpleLocalize language keys.
///
/// Language keys in SimpleLocalize are usually `en`, `pl`, `en_GB` or `pt-BR`, while
/// `Locale.preferredLanguages` returns BCP 47 tags such as `en-GB`. The resolver produces
/// an ordered list of candidates; the first one published on the CDN wins.
enum LanguageResolver {

  static func candidates(explicit: String?, preferredLanguages: [String] = Locale.preferredLanguages) -> [String] {
    if let explicit, !explicit.isEmpty {
      return [explicit]
    }
    var result: [String] = []
    for tag in preferredLanguages {
      for candidate in variants(of: tag) where !result.contains(candidate) {
        result.append(candidate)
      }
    }
    return result
  }

  /// `en-GB` -> `en_GB`, `en-GB`, `en`
  static func variants(of tag: String) -> [String] {
    let normalized = tag.replacingOccurrences(of: "_", with: "-")
    let parts = normalized.split(separator: "-").map(String.init)
    guard let language = parts.first?.lowercased() else { return [] }

    var result: [String] = []
    // Drop script subtags such as `zh-Hans-CN` -> region `CN`.
    let region = parts.dropFirst().first(where: { $0.count == 2 || $0.allSatisfy(\.isNumber) })?.uppercased()
    if let region {
      result.append("\(language)_\(region)")
      result.append("\(language)-\(region)")
    }
    result.append(language)
    return result
  }
}
