import XCTest
@testable import SimpleLocalizeOTA

final class TranslationJSONTests: XCTestCase {

  func testParsesFlatPayload() throws {
    let data = Data(#"{"home.title":"Cześć","home.subtitle":"Witaj"}"#.utf8)
    let translations = try TranslationJSON.parse(data)
    XCTAssertEqual(translations["home.title"], "Cześć")
    XCTAssertEqual(translations.count, 2)
  }

  func testFlattensNestedPayload() throws {
    let data = Data(#"{"home":{"title":"Cześć","cta":{"label":"Dalej"}},"count":7}"#.utf8)
    let translations = try TranslationJSON.parse(data)
    XCTAssertEqual(translations["home.title"], "Cześć")
    XCTAssertEqual(translations["home.cta.label"], "Dalej")
    XCTAssertEqual(translations["count"], "7")
  }

  func testRejectsNonObjectPayload() {
    XCTAssertThrowsError(try TranslationJSON.parse(Data("[1,2,3]".utf8)))
  }
}

final class TranslationResourceTests: XCTestCase {

  func testDefaultResourcePath() {
    let resource = TranslationResource(language: "pl_PL")
    XCTAssertEqual(resource.path(projectToken: "TOKEN", environment: "_production"), "TOKEN/_production/pl_PL")
  }

  func testNamespaceAndCustomerPath() {
    let resource = TranslationResource(language: "en", namespace: "checkout", customerId: "acme")
    XCTAssertEqual(resource.path(projectToken: "TOKEN", environment: "_latest"), "TOKEN/_latest/en_acme/checkout")
  }

  func testResourceURL() {
    let resource = TranslationResource(language: "en", namespace: "checkout")
    let url = resource.url(
      projectToken: "TOKEN",
      environment: "_production",
      baseURL: URL(string: "https://cdn.simplelocalize.io")!
    )
    XCTAssertEqual(url.absoluteString, "https://cdn.simplelocalize.io/TOKEN/_production/en/checkout")
  }

  func testCacheFileNameIsFileSystemSafe() {
    let resource = TranslationResource(language: "pt-BR", namespace: "emails/transactional", customerId: "acme")
    XCTAssertEqual(resource.cacheFileName, "pt-BR_acme.emails-transactional.json")
  }
}

final class LanguageResolverTests: XCTestCase {

  func testExplicitLanguageWins() {
    XCTAssertEqual(LanguageResolver.candidates(explicit: "de_DE", preferredLanguages: ["pl-PL"]), ["de_DE"])
  }

  func testCandidatesFromPreferredLanguages() {
    let candidates = LanguageResolver.candidates(explicit: nil, preferredLanguages: ["en-GB", "pl-PL"])
    XCTAssertEqual(candidates, ["en_GB", "en-GB", "en", "pl_PL", "pl-PL", "pl"])
  }

  func testScriptSubtagIsSkipped() {
    XCTAssertEqual(LanguageResolver.variants(of: "zh-Hans-CN"), ["zh_CN", "zh-CN", "zh"])
  }
}

final class TranslationStoreTests: XCTestCase {

  func testLookupFallsBackToSecondLanguage() {
    let store = TranslationStore()
    store.replace(language: "pl", namespace: "", translations: ["a": "A-pl"])
    store.replace(language: "en", namespace: "", translations: ["a": "A-en", "b": "B-en"])
    XCTAssertEqual(store.lookup(key: "a", namespace: "", languages: ["pl", "en"]), "A-pl")
    XCTAssertEqual(store.lookup(key: "b", namespace: "", languages: ["pl", "en"]), "B-en")
    XCTAssertNil(store.lookup(key: "c", namespace: "", languages: ["pl", "en"]))
  }

  func testEmptyTranslationIsTreatedAsMissing() {
    let store = TranslationStore()
    store.replace(language: "pl", namespace: "", translations: ["a": ""])
    store.replace(language: "en", namespace: "", translations: ["a": "A-en"])
    XCTAssertEqual(store.lookup(key: "a", namespace: "", languages: ["pl", "en"]), "A-en")
  }

  func testRevisionChangesOnlyOnRealChange() {
    let store = TranslationStore()
    XCTAssertTrue(store.replace(language: "pl", namespace: "", translations: ["a": "A"]))
    let revision = store.revision
    XCTAssertFalse(store.replace(language: "pl", namespace: "", translations: ["a": "A"]))
    XCTAssertEqual(store.revision, revision)
  }
}

final class TranslationCacheTests: XCTestCase {

  func testWriteAndReadRoundTrip() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let cache = TranslationCache(directory: directory)
    let resource = TranslationResource(language: "pl")
    try cache.write(.init(etag: "\"abc\"", updatedAt: Date(), translations: ["a": "A"]), for: resource)

    let entry = cache.read(resource)
    XCTAssertEqual(entry?.etag, "\"abc\"")
    XCTAssertEqual(entry?.translations["a"], "A")

    cache.clear()
    XCTAssertNil(cache.read(resource))
  }
}
