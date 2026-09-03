import XCTest
@testable import SimpleLocalizeOTA

final class SimpleLocalizeTests: XCTestCase {

  private var cacheDirectory: URL!

  override func setUp() {
    super.setUp()
    cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: cacheDirectory)
    super.tearDown()
  }

  private func makeConfiguration(
    language: String? = "pl",
    fallbackLanguage: String? = nil,
    namespaces: [String] = []
  ) -> SimpleLocalizeConfiguration {
    SimpleLocalizeConfiguration(
      projectToken: "TOKEN-\(UUID().uuidString)",
      environment: "_production",
      namespaces: namespaces,
      language: language,
      fallbackLanguage: fallbackLanguage,
      refreshOnForeground: false,
      session: StubURLProtocol.makeSession()
    )
  }

  private func refreshAndWait(_ sdk: SimpleLocalize, file: StaticString = #filePath, line: UInt = #line) -> Result<Void, Error> {
    let expectation = expectation(description: "refresh")
    var outcome: Result<Void, Error>!
    sdk.refresh { result in
      outcome = result
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 5)
    return outcome
  }

  func testDownloadsAndServesTranslations() {
    StubURLProtocol.setHandler { _ in
      .init(statusCode: 200, body: Data(#"{"home.title":"Cześć"}"#.utf8), headers: ["Etag": "\"v1\""])
    }
    let sdk = SimpleLocalize()
    sdk.start(makeConfiguration(), cacheDirectory: cacheDirectory)
    _ = refreshAndWait(sdk)

    XCTAssertEqual(sdk.otaString(forKey: "home.title"), "Cześć")
    XCTAssertEqual(sdk.currentLanguage, "pl")
    XCTAssertTrue(StubURLProtocol.requests.contains { $0.url?.path.hasSuffix("/_production/pl") == true })
  }

  func testMissingKeyFallsBackToBundle() {
    StubURLProtocol.setHandler { _ in
      .init(statusCode: 200, body: Data(#"{"home.title":"Cześć"}"#.utf8))
    }
    let sdk = SimpleLocalize()
    sdk.start(makeConfiguration(), cacheDirectory: cacheDirectory)
    _ = refreshAndWait(sdk)

    XCTAssertNil(sdk.otaString(forKey: "unknown.key"))
    // No bundled strings in the test bundle, so NSLocalizedString semantics apply: the key itself.
    XCTAssertEqual(sdk.string("unknown.key"), "unknown.key")
    XCTAssertEqual(sdk.string("unknown.key", defaultValue: "Default"), "Default")
  }

  func testSecondRefreshSendsIfNoneMatchAndKeepsTranslationsOn304() {
    StubURLProtocol.setHandler { request in
      if request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" {
        return .init(statusCode: 304)
      }
      return .init(statusCode: 200, body: Data(#"{"home.title":"Cześć"}"#.utf8), headers: ["Etag": "\"v1\""])
    }
    let sdk = SimpleLocalize()
    sdk.start(makeConfiguration(), cacheDirectory: cacheDirectory)
    _ = refreshAndWait(sdk)
    let revisionAfterFirstRefresh = sdk.revision

    _ = refreshAndWait(sdk)
    XCTAssertEqual(sdk.otaString(forKey: "home.title"), "Cześć")
    XCTAssertEqual(sdk.revision, revisionAfterFirstRefresh, "304 must not bump the revision")
    XCTAssertTrue(StubURLProtocol.requests.contains { $0.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" })
  }

  func testStartsFromDiskCacheWhenNetworkFails() {
    let configuration = makeConfiguration()
    StubURLProtocol.setHandler { _ in
      .init(statusCode: 200, body: Data(#"{"home.title":"Cześć"}"#.utf8), headers: ["Etag": "\"v1\""])
    }
    let first = SimpleLocalize()
    first.start(configuration, cacheDirectory: cacheDirectory)
    _ = refreshAndWait(first)

    StubURLProtocol.setHandler { _ in .init(statusCode: 500) }
    let second = SimpleLocalize()
    second.start(configuration, cacheDirectory: cacheDirectory)

    // Available immediately after start(), before any network call finishes.
    XCTAssertEqual(second.otaString(forKey: "home.title"), "Cześć")
    let result = refreshAndWait(second)
    if case .success = result {
      XCTFail("HTTP 500 should surface as a failure")
    }
    XCTAssertEqual(second.otaString(forKey: "home.title"), "Cześć", "a failed refresh must not drop cached content")
  }

  func testUnpublishedLanguageReportsError() {
    StubURLProtocol.setHandler { _ in .init(statusCode: 404) }
    let sdk = SimpleLocalize()
    sdk.start(makeConfiguration(language: "xx"), cacheDirectory: cacheDirectory)

    let result = refreshAndWait(sdk)
    switch result {
    case .success:
      XCTFail("Expected a failure for an unpublished language")
    case .failure(let error):
      guard case SimpleLocalizeError.languageNotAvailable = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
    XCTAssertNil(sdk.currentLanguage)
  }

  func testNamespacesMapToTables() {
    StubURLProtocol.setHandler { request in
      let path = request.url?.path ?? ""
      if path.hasSuffix("/pl/checkout") {
        return .init(statusCode: 200, body: Data(#"{"pay":"Zapłać"}"#.utf8))
      }
      if path.hasSuffix("/pl/common") {
        return .init(statusCode: 200, body: Data(#"{"ok":"OK"}"#.utf8))
      }
      return .init(statusCode: 404)
    }
    let sdk = SimpleLocalize()
    sdk.start(makeConfiguration(namespaces: ["common", "checkout"]), cacheDirectory: cacheDirectory)
    _ = refreshAndWait(sdk)

    XCTAssertEqual(sdk.otaString(forKey: "pay", table: "checkout"), "Zapłać")
    XCTAssertEqual(sdk.otaString(forKey: "ok", table: "common"), "OK")
    // Without a table the default namespace is searched first, then the remaining ones.
    XCTAssertEqual(sdk.otaString(forKey: "pay"), "Zapłać")
  }

  func testFallbackLanguageIsUsedForMissingKeys() {
    StubURLProtocol.setHandler { request in
      let path = request.url?.path ?? ""
      if path.hasSuffix("/pl") {
        return .init(statusCode: 200, body: Data(#"{"home.title":"Cześć"}"#.utf8))
      }
      return .init(statusCode: 200, body: Data(#"{"home.title":"Hi","home.cta":"Continue"}"#.utf8))
    }
    let sdk = SimpleLocalize()
    sdk.start(makeConfiguration(fallbackLanguage: "en"), cacheDirectory: cacheDirectory)
    _ = refreshAndWait(sdk)

    XCTAssertEqual(sdk.otaString(forKey: "home.title"), "Cześć")
    XCTAssertEqual(sdk.otaString(forKey: "home.cta"), "Continue")
  }

  func testSetLanguageSwitchesContent() {
    StubURLProtocol.setHandler { request in
      let path = request.url?.path ?? ""
      let body = path.hasSuffix("/de") ? #"{"home.title":"Hallo"}"# : #"{"home.title":"Cześć"}"#
      return .init(statusCode: 200, body: Data(body.utf8))
    }
    let sdk = SimpleLocalize()
    sdk.start(makeConfiguration(), cacheDirectory: cacheDirectory)
    _ = refreshAndWait(sdk)
    XCTAssertEqual(sdk.otaString(forKey: "home.title"), "Cześć")

    let expectation = expectation(description: "language switched")
    sdk.setLanguage("de") { _ in expectation.fulfill() }
    wait(for: [expectation], timeout: 5)

    XCTAssertEqual(sdk.currentLanguage, "de")
    XCTAssertEqual(sdk.otaString(forKey: "home.title"), "Hallo")
  }

  func testBundleIntegrationInterceptsNSLocalizedString() {
    StubURLProtocol.setHandler { _ in
      .init(statusCode: 200, body: Data(#"{"home.title":"Cześć"}"#.utf8))
    }
    SimpleLocalize.shared.start(makeConfiguration(), cacheDirectory: cacheDirectory)
    _ = refreshAndWait(SimpleLocalize.shared)

    SimpleLocalize.enableBundleIntegration()
    defer {
      SimpleLocalize.disableBundleIntegration()
      SimpleLocalize.shared.stop()
    }

    XCTAssertTrue(SimpleLocalize.isBundleIntegrationEnabled)
    XCTAssertEqual(NSLocalizedString("home.title", comment: ""), "Cześć")
    XCTAssertEqual(NSLocalizedString("not.downloaded", comment: ""), "not.downloaded")
  }
}
