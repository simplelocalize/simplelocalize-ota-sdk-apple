import Foundation

/// Parses Translation Hosting payloads.
///
/// Hosting can publish translations either flat (`{"home.title": "Hi"}`) or nested
/// (`{"home": {"title": "Hi"}}`), depending on project settings. Both shapes are
/// flattened into dot separated keys so lookups stay identical.
enum TranslationJSON {

  static func parse(_ data: Data) throws -> [String: String] {
    let json = try JSONSerialization.jsonObject(with: data, options: [])
    guard let object = json as? [String: Any] else {
      throw SimpleLocalizeError.invalidResponse
    }
    var result: [String: String] = [:]
    flatten(object, prefix: "", into: &result)
    return result
  }

  private static func flatten(_ object: [String: Any], prefix: String, into result: inout [String: String]) {
    for (key, value) in object {
      let path = prefix.isEmpty ? key : prefix + "." + key
      switch value {
      case let string as String:
        result[path] = string
      case let nested as [String: Any]:
        flatten(nested, prefix: path, into: &result)
      case let number as NSNumber:
        result[path] = number.stringValue
      default:
        continue
      }
    }
  }
}
