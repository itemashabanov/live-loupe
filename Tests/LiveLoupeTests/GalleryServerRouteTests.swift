import XCTest
@testable import LiveLoupe

final class GalleryServerRouteTests: XCTestCase {
    func testRootRedirectsToScreenWhenLiveModeIsActive() {
        XCTAssertEqual(
            GalleryServer.routeDecision(for: "/", mode: .screen),
            .redirect("/screen")
        )
    }

    func testScreenRedirectsToRootWhenExportModeIsActive() {
        XCTAssertEqual(
            GalleryServer.routeDecision(for: "/screen", mode: .export),
            .redirect("/")
        )
    }

    func testModeSpecificDataEndpointsStayBlocked() {
        XCTAssertEqual(
            GalleryServer.routeDecision(for: "/screen.mjpg", mode: .export),
            .unavailable
        )
        XCTAssertEqual(
            GalleryServer.routeDecision(for: "/manifest.json", mode: .screen),
            .unavailable
        )
    }
}
