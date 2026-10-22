import Foundation
import CryptoKit
import Security

/// VULCAN Hebe RSA request signing (PKCS#1 v1.5 / SHA-256).
enum Signing {
    static func makeCredential(deviceModel: String = "iPhone", deviceOS: String = "iOS") throws -> HebeCredential {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw VulcanError.message("Nie udało się wygenerować klucza RSA.")
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw VulcanError.message("Nie udało się odczytać klucza publicznego.")
        }
        guard let publicRef = SecKeyCopyExternalRepresentation(publicKey, &error) else {
            throw VulcanError.message("Nie udało się wyeksportować klucza publicznego.")
        }
        guard let privateRef = SecKeyCopyExternalRepresentation(privateKey, &error) else {
            throw VulcanError.message("Nie udało się wyeksportować klucza prywatnego.")
        }

        let spki = spkiFromPKCS1(publicRef as Data)
        let pem = pemString(spki)
        return HebeCredential(
            type: "RSA_PEM",
            restUrl: nil,
            certificate: spki.base64EncodedString(),
            privateKey: (privateRef as Data).base64EncodedString(),
            fingerprint: md5Hex(Data(pem.utf8)),
            deviceId: UUID().uuidString,
            deviceOs: deviceOS,
            deviceModel: deviceModel,
            notificationToken: nil
        )
    }

    static func signatureDate(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'Z"
        return formatter.string(from: date)
    }

    /// Returns every header required by the API, including Signature and Digest.
    static func headers(credential: HebeCredential, body: Data?, url: String, date: Date = Date()) throws -> [String: String] {
        let canonical = canonicalURL(url)
        let formattedDate = signatureDate(date)

        var names = ["vCanonicalUrl"]
        var content = canonical
        var result: [String: String] = [
            "vCanonicalUrl": canonical,
            "vDate": formattedDate
        ]

        if let body, !body.isEmpty {
            let digest = Data(SHA256.hash(data: body)).base64EncodedString()
            names.append("Digest")
            content += digest
            result["Digest"] = "SHA-256=" + digest
        }

        names.append("vDate")
        content += formattedDate

        let signature = try sign(content: Data(content.utf8), privateKeyBase64: credential.privateKey)
        let signatureHeader = "keyId=\"\(credential.fingerprint)\",headers=\"\(names.joined(separator: " "))\",algorithm=\"sha256\",signature=Base64(sha256withrsa(\(signature)))"
        result["Signature"] = signatureHeader
        return result
    }

    static func canonicalURL(_ url: String) -> String {
        let pattern = "api/mobile/.+"
        let range = url.range(of: pattern, options: .regularExpression)
        let path = range.map { String(url[$0]) } ?? url
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._*"))
        let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        return encoded.lowercased()
    }

    private static func sign(content: Data, privateKeyBase64: String) throws -> String {
        guard let keyData = Data(base64Encoded: privateKeyBase64) else {
            throw VulcanError.message("Nieprawidłowy klucz prywatny.")
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw VulcanError.message("Nie udało się odczytać klucza prywatnego.")
        }
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            content as CFData,
            &error
        ) else {
            throw VulcanError.message("Nie udało się podpisać żądania.")
        }
        return (signature as Data).base64EncodedString()
    }

    private static func spkiFromPKCS1(_ pkcs1: Data) -> Data {
        let algorithm: [UInt8] = [
            0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
            0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00
        ]
        var bitString = Data([0x03])
        bitString.append(derLength(pkcs1.count + 1))
        bitString.append(0x00)
        bitString.append(pkcs1)

        var content = Data(algorithm)
        content.append(bitString)

        var spki = Data([0x30])
        spki.append(derLength(content.count))
        spki.append(content)
        return spki
    }

    private static func derLength(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        }
        if length <= 0xFF {
            return Data([0x81, UInt8(length)])
        }
        if length <= 0xFFFF {
            return Data([0x82, UInt8(length >> 8), UInt8(length & 0xFF)])
        }
        return Data([
            0x83,
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF)
        ])
    }

    private static func pemString(_ der: Data) -> String {
        let base64 = der.base64EncodedString()
        var lines: [String] = []
        var index = base64.startIndex
        while index < base64.endIndex {
            let end = base64.index(index, offsetBy: 64, limitedBy: base64.endIndex) ?? base64.endIndex
            lines.append(String(base64[index..<end]))
            index = end
        }
        return "-----BEGIN PUBLIC KEY-----\n" + lines.joined(separator: "\n") + "\n-----END PUBLIC KEY-----\n"
    }

    private static func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
