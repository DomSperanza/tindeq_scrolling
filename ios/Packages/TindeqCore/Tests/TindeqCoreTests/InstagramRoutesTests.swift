import XCTest
@testable import TindeqCore

final class InstagramRoutesTests: XCTestCase {
    private func route(_ string: String) -> InstagramRoutes.Route {
        InstagramRoutes.classify(URL(string: string))
    }

    func testReels() {
        XCTAssertEqual(route("https://www.instagram.com/reels/"), .reels)
        XCTAssertEqual(route("https://www.instagram.com/reels/C9abcDEF/"), .reels)
        XCTAssertEqual(route("https://www.instagram.com/reel/C9abcDEF/?igsh=x"), .reels)
        XCTAssertEqual(route("https://instagram.com/reels/"), .reels)
        XCTAssertEqual(route("https://www.instagram.com/reels"), .reels)
    }

    func testAuth() {
        XCTAssertEqual(route("https://www.instagram.com/accounts/login/?next=%2Freels%2F"), .auth)
        XCTAssertEqual(route("https://www.instagram.com/accounts/onetap/?next=%2F"), .auth)
        XCTAssertEqual(route("https://www.instagram.com/challenge/action/"), .auth)
        XCTAssertEqual(route("https://www.instagram.com/accounts/"), .auth)
        XCTAssertEqual(route("https://m.facebook.com/login.php"), .auth)
    }

    func testBlocked() {
        XCTAssertEqual(route("https://www.instagram.com/"), .blocked)
        XCTAssertEqual(route("https://www.instagram.com"), .blocked)
        XCTAssertEqual(route("https://www.instagram.com/explore/"), .blocked)
        XCTAssertEqual(route("https://www.instagram.com/direct/inbox/"), .blocked)
        XCTAssertEqual(route("https://www.instagram.com/someuser/"), .blocked)
        // Usernames that merely start with "reel(s)" are profiles, not reels.
        XCTAssertEqual(route("https://www.instagram.com/reelfan/"), .blocked)
        XCTAssertEqual(route("https://www.instagram.com/reelsfan/"), .blocked)
        XCTAssertEqual(route("https://www.instagram.com/accountsguy/"), .blocked)
    }

    func testExternal() {
        XCTAssertEqual(route("https://l.instagram.com/?u=https%3A%2F%2Fexample.com"), .external)
        XCTAssertEqual(route("https://example.com/reels/"), .external)
        XCTAssertEqual(route("https://notinstagram.com/reels/"), .external)
        XCTAssertEqual(route("instagram://reels"), .external)
        XCTAssertEqual(InstagramRoutes.classify(nil), .external)
    }

    func testBridgeConfigScript() {
        let script = InstagramRoutes.bridgeConfigScript()
        XCTAssertTrue(script.hasPrefix("window.__tindeqConfig = {"))
        XCTAssertTrue(script.contains("reelsSegments: ['reels','reel']"))
    }
}
