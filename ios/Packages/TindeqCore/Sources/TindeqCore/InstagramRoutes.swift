import Foundation

/// Reels-only navigation policy for the in-app Instagram web view.
/// The same lists are handed to `ReelsBridge.js` so link blocking in the page
/// and navigation blocking in Swift agree.
public enum InstagramRoutes {
    public enum Route: Equatable, Sendable {
        /// Reels feed or a single reel: the pull gate is active here.
        case reels
        /// Login, 2FA, checkpoints, consent: allowed, gate paused so the user can type.
        case auth
        /// Any other Instagram page (home feed, profiles, explore, DMs): not allowed.
        case blocked
        /// Not Instagram at all.
        case external
    }

    public static let reelsURL = URL(string: "https://www.instagram.com/reels/")!

    /// Matched against the first path segment, e.g. "reels" in /reels/C9abc/.
    public static let reelsSegments = ["reels", "reel"]
    public static let authSegments = ["accounts", "challenge", "two_factor", "auth_platform", "consent"]
    /// "Continue with Facebook" login happens on these hosts.
    public static let authHostSuffixes = ["facebook.com"]

    public static func classify(_ url: URL?) -> Route {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else {
            return .external
        }
        if authHostSuffixes.contains(where: { hostMatches(host, $0) }) {
            return .auth
        }
        // l.instagram.com is the outbound link shim.
        guard hostMatches(host, "instagram.com"), host != "l.instagram.com" else {
            return .external
        }
        let segment = firstSegment(url.path)
        if reelsSegments.contains(segment) {
            return .reels
        }
        if authSegments.contains(segment) {
            return .auth
        }
        return .blocked
    }

    /// JS prelude for `ReelsBridge.js`.
    public static func bridgeConfigScript() -> String {
        func jsArray(_ values: [String]) -> String {
            "[" + values.map { "'\($0)'" }.joined(separator: ",") + "]"
        }
        return "window.__tindeqConfig = {"
            + "reelsSegments: \(jsArray(reelsSegments)),"
            + "authSegments: \(jsArray(authSegments)),"
            + "authHostSuffixes: \(jsArray(authHostSuffixes))"
            + "};\n"
    }

    static func firstSegment(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }

    private static func hostMatches(_ host: String, _ suffix: String) -> Bool {
        host == suffix || host.hasSuffix("." + suffix)
    }
}
