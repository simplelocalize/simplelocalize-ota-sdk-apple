import Foundation
import ObjectiveC

/// `Bundle.main` replacement that answers with over-the-air translations first.
private final class SimpleLocalizeBundle: Bundle, @unchecked Sendable {
  override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
    if let translation = SimpleLocalize.shared.otaString(forKey: key, table: tableName) {
      return translation
    }
    return super.localizedString(forKey: key, value: value, table: tableName)
  }
}

public extension SimpleLocalize {

  /// Makes existing `NSLocalizedString` / `String(localized:)` / SwiftUI `Text("key")` calls
  /// return over-the-air translations, without touching call sites.
  ///
  /// It swaps the class of `Bundle.main` (no method swizzling of shared classes), and keys
  /// that were not downloaded fall through to the strings compiled into the app.
  ///
  /// Call it once, before the first UI is built. Views already on screen are not re-rendered
  /// automatically - observe ``SimpleLocalize/translationsDidChangeNotification`` for that.
  static func enableBundleIntegration() {
    guard !isBundleIntegrationEnabled else { return }
    object_setClass(Bundle.main, SimpleLocalizeBundle.self)
  }

  static func disableBundleIntegration() {
    guard isBundleIntegrationEnabled else { return }
    object_setClass(Bundle.main, Bundle.self)
  }

  static var isBundleIntegrationEnabled: Bool {
    object_getClass(Bundle.main) == SimpleLocalizeBundle.self
  }
}
