#if canImport(SwiftUI) && canImport(Combine)
import SwiftUI
import Combine

/// Observable wrapper that re-renders SwiftUI views when new translations arrive.
///
/// ```swift
/// @StateObject private var localization = SimpleLocalizeObservable()
///
/// var body: some View {
///   Text(localization.string("home.title"))
/// }
/// ```
@available(iOS 13.0, macOS 11.0, tvOS 13.0, watchOS 6.0, *)
public final class SimpleLocalizeObservable: ObservableObject {

  @Published public private(set) var revision: Int

  private var cancellable: AnyCancellable?
  private let simpleLocalize: SimpleLocalize

  public init(_ simpleLocalize: SimpleLocalize = .shared) {
    self.simpleLocalize = simpleLocalize
    self.revision = simpleLocalize.revision
    cancellable = NotificationCenter.default
      .publisher(for: SimpleLocalize.translationsDidChangeNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self else { return }
        self.revision = self.simpleLocalize.revision
      }
  }

  public func string(_ key: String, table: String? = nil, defaultValue: String? = nil) -> String {
    simpleLocalize.string(key, table: table, defaultValue: defaultValue)
  }

  public var currentLanguage: String? { simpleLocalize.currentLanguage }

  public func setLanguage(_ language: String?) {
    simpleLocalize.setLanguage(language)
  }
}

@available(iOS 13.0, macOS 11.0, tvOS 13.0, watchOS 6.0, *)
public extension Text {
  /// `Text(simpleLocalized: "home.title")` - resolved through Translation Hosting.
  init(simpleLocalized key: String, table: String? = nil) {
    self.init(SimpleLocalize.shared.string(key, table: table))
  }
}

@available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
private struct SimpleLocalizeAwareModifier: ViewModifier {
  @StateObject private var localization = SimpleLocalizeObservable()

  func body(content: Content) -> some View {
    content.id(localization.revision)
  }
}

@available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
public extension View {
  /// Rebuilds the view subtree when translations change, so `Text(simpleLocalized:)` and
  /// `"key".simpleLocalized` show freshly downloaded content.
  func simpleLocalizeAware() -> some View {
    modifier(SimpleLocalizeAwareModifier())
  }
}
#endif
