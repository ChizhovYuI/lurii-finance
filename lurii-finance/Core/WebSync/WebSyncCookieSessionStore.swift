import Foundation
import Security
import WebKit

private let httpOnlyPropertyKey = HTTPCookiePropertyKey("HttpOnly")
private let sameSitePropertyKey = HTTPCookiePropertyKey("SameSite")

private struct PersistedCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresAt: TimeInterval?
    let secure: Bool
    let httpOnly: Bool
    let sameSite: String?
}

@MainActor
final class WebSyncCookieSessionStore {
    private let service = "ai.lurii.finance.websync.cookies"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func saveCookies(from cookieStore: WKHTTPCookieStore, provider: WebSyncProvider) async {
        let cookies = await cookieStore.allCookies()
        persist(cookies: cookies, provider: provider)
    }

    func restoreCookies(into cookieStore: WKHTTPCookieStore, provider: WebSyncProvider) async {
        let cookies = persistedCookies(provider: provider)
        for cookie in cookies {
            await cookieStore.setCookieAsync(cookie)
        }
    }

    func persistCookies(_ cookies: [HTTPCookie], provider: WebSyncProvider) {
        persist(cookies: cookies, provider: provider)
    }

    func persistedCookies(provider: WebSyncProvider) -> [HTTPCookie] {
        guard let data = loadKeychainData(account: provider.rawValue) else { return [] }
        guard let records = try? decoder.decode([PersistedCookie].self, from: data) else { return [] }

        return records.compactMap { record in
            if let expiresAt = record.expiresAt, Date(timeIntervalSince1970: expiresAt) <= Date() {
                return nil
            }
            return makeCookie(from: record)
        }
    }

    private func persist(cookies: [HTTPCookie], provider: WebSyncProvider) {
        let records = cookies
            .filter { cookie in
                cookie.domain.lowercased().contains(provider.cookieDomainSuffix)
            }
            .map { cookie in
                PersistedCookie(
                    name: cookie.name,
                    value: cookie.value,
                    domain: cookie.domain,
                    path: cookie.path,
                    expiresAt: cookie.expiresDate?.timeIntervalSince1970,
                    secure: cookie.isSecure,
                    httpOnly: isHttpOnly(cookie: cookie),
                    sameSite: cookie.properties?[sameSitePropertyKey] as? String
                )
            }
        guard let data = try? encoder.encode(records) else { return }
        upsertKeychainData(data, account: provider.rawValue)
    }

    private func makeCookie(from record: PersistedCookie) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: record.name,
            .value: record.value,
            .domain: record.domain,
            .path: record.path
        ]
        if let expiresAt = record.expiresAt {
            properties[.expires] = Date(timeIntervalSince1970: expiresAt)
        }
        if record.secure {
            properties[.secure] = "TRUE"
        }
        if record.httpOnly {
            properties[httpOnlyPropertyKey] = "TRUE"
        }
        if let sameSite = record.sameSite {
            properties[sameSitePropertyKey] = sameSite
        }
        return HTTPCookie(properties: properties)
    }

    private func isHttpOnly(cookie: HTTPCookie) -> Bool {
        guard let rawValue = cookie.properties?[httpOnlyPropertyKey] as? String else { return false }
        return rawValue.caseInsensitiveCompare("true") == .orderedSame
    }

    private func upsertKeychainData(_ data: Data, account: String) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            return
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadKeychainData(account: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess {
            return nil
        }
        return result as? Data
    }
}

extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    func setCookieAsync(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            setCookie(cookie) {
                continuation.resume()
            }
        }
    }
}
