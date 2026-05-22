import XCTest
@testable import DocumentScanner

final class ICloudContainerTests: XCTestCase {

    func test_localDocumentsURL_endsInDocuments() {
        let container = ICloudContainer()
        let url = container.localDocumentsURL
        XCTAssertTrue(url.path.hasSuffix("/Documents"),
                      "expected path ending in /Documents, got \(url.path)")
    }

    func test_resolveDocumentsURL_returnsLocalWhenICloudUnavailable() {
        let container = ICloudContainer(iCloudURLProvider: { nil })
        XCTAssertEqual(container.resolveDocumentsURL(), container.localDocumentsURL)
    }

    func test_resolveDocumentsURL_returnsICloudWhenAvailable() {
        let stubURL = URL(fileURLWithPath: "/tmp/fake-icloud/Documents")
        let container = ICloudContainer(iCloudURLProvider: { stubURL })
        XCTAssertEqual(container.resolveDocumentsURL(), stubURL)
    }
}
