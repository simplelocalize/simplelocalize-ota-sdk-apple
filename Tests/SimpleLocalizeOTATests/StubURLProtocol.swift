import Foundation

/// Fake network layer for tests: serves canned responses per URL path.
final class StubURLProtocol: URLProtocol {

  struct Response {
    var statusCode: Int
    var body: Data?
    var headers: [String: String]

    init(statusCode: Int, body: Data? = nil, headers: [String: String] = [:]) {
      self.statusCode = statusCode
      self.body = body
      self.headers = headers
    }
  }

  private static let lock = NSLock()
  private static var handler: ((URLRequest) -> Response)?
  private static var requestLog: [URLRequest] = []

  static func setHandler(_ handler: @escaping (URLRequest) -> Response) {
    lock.lock()
    self.handler = handler
    requestLog = []
    lock.unlock()
  }

  static var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return requestLog
  }

  static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    configuration.urlCache = nil
    return URLSession(configuration: configuration)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    Self.requestLog.append(request)
    let handler = Self.handler
    Self.lock.unlock()

    guard let handler, let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    let stub = handler(request)
    let response = HTTPURLResponse(
      url: url,
      statusCode: stub.statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: stub.headers
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    if let body = stub.body {
      client?.urlProtocol(self, didLoad: body)
    }
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
