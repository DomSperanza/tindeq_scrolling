import WebKit

/// Instagram login lives in the default (persistent) WKWebsiteDataStore, so it
/// survives app restarts just like Safari.
@MainActor
enum InstagramAccount {
    static func isSignedIn() async -> Bool {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return cookies.contains { cookie in
            cookie.name == "sessionid" && cookie.domain.hasSuffix("instagram.com") && !cookie.value.isEmpty
        }
    }

    static func signOut() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }
}
