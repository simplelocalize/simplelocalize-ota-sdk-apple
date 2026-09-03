import Foundation

/// Downloads a single hosting resource using a conditional GET.
final class TranslationLoader {

  enum Outcome {
    case updated(translations: [String: String], etag: String?)
    case notModified
    case notFound
  }

  private let session: URLSession

  init(session: URLSession) {
    self.session = session
  }

  func load(url: URL, etag: String?, completion: @escaping (Result<Outcome, Error>) -> Void) {
    // The CDN sets its own Cache-Control; URLCache would hide the revalidation from us,
    // so the request always goes out and the ETag decides whether a body is transferred.
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let etag, !etag.isEmpty {
      request.setValue(etag, forHTTPHeaderField: "If-None-Match")
    }

    session.dataTask(with: request) { data, response, error in
      if let error {
        completion(.failure(error))
        return
      }
      guard let http = response as? HTTPURLResponse else {
        completion(.failure(SimpleLocalizeError.invalidResponse))
        return
      }
      switch http.statusCode {
      case 304:
        completion(.success(.notModified))
      case 404:
        completion(.success(.notFound))
      case 200..<300:
        guard let data else {
          completion(.failure(SimpleLocalizeError.invalidResponse))
          return
        }
        do {
          let translations = try TranslationJSON.parse(data)
          let newEtag = http.value(forHTTPHeaderField: "Etag") ?? http.value(forHTTPHeaderField: "ETag")
          completion(.success(.updated(translations: translations, etag: newEtag)))
        } catch {
          completion(.failure(error))
        }
      default:
        completion(.failure(SimpleLocalizeError.httpStatus(http.statusCode)))
      }
    }.resume()
  }
}
