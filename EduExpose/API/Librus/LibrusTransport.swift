import Foundation

/// A transport-neutral request. The session actor adds the cookie header;
/// the transport never reads the shared cookie storage.
struct LibrusRequest: Sendable {
    var url: URL
    var method: String = "GET"
    var headers: [String: String] = [:]
    var body: Data?
    var timeout: TimeInterval = LibrusConstants.requestTimeout
    var followsRedirects: Bool = false
}

struct LibrusHTTPResponse: Sendable {
    let url: URL
    let status: Int
    let headers: [String: String]
    let setCookie: [String]
    let body: Data

    init(
        url: URL,
        status: Int,
        headers: [String: String] = [:],
        setCookie: [String] = [],
        body: Data = Data()
    ) {
        self.url = url
        self.status = status
        self.headers = headers
        self.setCookie = setCookie
        self.body = body
    }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    var text: String {
        let contentType = header("content-type")?.lowercased() ?? ""
        let encoding = Self.stringEncoding(from: contentType)
        if let encoding, let text = String(data: body, encoding: encoding) {
            return Self.strippingBOM(text)
        }
        return Self.strippingBOM(String(decoding: body, as: UTF8.self))
    }

    private static func strippingBOM(_ text: String) -> String {
        guard text.hasPrefix("\u{FEFF}") else { return text }
        return String(text.dropFirst())
    }

    private static func stringEncoding(from contentType: String) -> String.Encoding? {
        guard let range = contentType.range(of: "charset=") else { return nil }
        let tail = contentType[range.upperBound...]
        let first = tail.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
        let raw = first.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        switch raw.lowercased() {
        case "utf-8", "utf8":
            return .utf8
        case "iso-8859-2", "latin2", "iso8859-2":
            return .isoLatin2
        case "windows-1250", "cp1250":
            return .windowsCP1250
        default:
            return nil
        }
    }
}

enum LibrusTransportError: Error, Sendable {
    case network
    case cancelled
    case invalidResponse
    case tooLarge
}

protocol LibrusTransport: Sendable {
    func send(_ request: LibrusRequest) async throws -> LibrusHTTPResponse
}

/// URLSession-based transport with no shared cookies, no disk cache and no
/// automatic redirects. The login handshake walks redirects itself.
final class URLSessionLibrusTransport: LibrusTransport, @unchecked Sendable {
    private let session: URLSession
    private let noRedirect = NoRedirectDelegate()

    init(configuration: URLSessionConfiguration? = nil) {
        let configuration = configuration ?? Self.makeConfiguration()
        session = URLSession(configuration: configuration)
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = LibrusConstants.requestTimeout
        configuration.timeoutIntervalForResource = LibrusConstants.resourceTimeout
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return configuration
    }

    func send(_ request: LibrusRequest) async throws -> LibrusHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest, delegate: noRedirect)
            guard let http = response as? HTTPURLResponse else {
                throw LibrusTransportError.invalidResponse
            }
            guard data.count <= LibrusConstants.maximumBodyBytes else {
                throw LibrusTransportError.tooLarge
            }
            let url = http.url ?? request.url
            return LibrusHTTPResponse(
                url: url,
                status: http.statusCode,
                headers: normalizedHeaders(http.allHeaderFields),
                setCookie: setCookieHeaders(http.allHeaderFields),
                body: data
            )
        } catch let error as LibrusTransportError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled {
                throw LibrusTransportError.cancelled
            }
            throw LibrusTransportError.network
        } catch {
            throw LibrusTransportError.network
        }
    }

    private func normalizedHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in headers {
            let name = String(describing: key).lowercased()
            if let text = value as? String {
                result[name] = text
            } else if let values = value as? [String] {
                result[name] = values.joined(separator: ", ")
            }
        }
        return result
    }

    private func setCookieHeaders(_ headers: [AnyHashable: Any]) -> [String] {
        var result: [String] = []
        for (key, value) in headers {
            guard String(describing: key).lowercased() == "set-cookie" else { continue }
            if let text = value as? String {
                result.append(contentsOf: LibrusCookie.splitCombined(text))
            } else if let values = value as? [String] {
                for value in values {
                    result.append(contentsOf: LibrusCookie.splitCombined(value))
                }
            }
        }
        return result
    }
}
