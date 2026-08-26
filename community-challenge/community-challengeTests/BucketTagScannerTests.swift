import XCTest
@testable import community_challenge

/// The payload shapes a real tag turns up carrying.
final class BucketTagScannerTests: XCTestCase {
    private let sensorID = UUID(uuidString: "0F5D2C7A-1B44-4E90-9C11-A3F2E1C09D77")!

    func testReadsABareUUID() {
        XCTAssertEqual(
            BucketTagScanner.sensorID(inText: sensorID.uuidString),
            sensorID
        )
    }

    /// The one that failed in the field: a tag written by hand carried
    /// `penyu:sensor:<uuid>`, and parsing the whole payload as a UUID rejected
    /// it as "not a bucket tag".
    func testReadsALabelledUUID() {
        XCTAssertEqual(
            BucketTagScanner.sensorID(inText: "penyu:sensor:\(sensorID.uuidString)"),
            sensorID
        )
    }

    func testIgnoresSurroundingWhitespaceAndCase() {
        XCTAssertEqual(
            BucketTagScanner.sensorID(
                inText: "  sensor = \(sensorID.uuidString.lowercased())  \n"
            ),
            sensorID
        )
    }

    func testRejectsTextWithNoUUID() {
        XCTAssertNil(BucketTagScanner.sensorID(inText: "https://google.com"))
        XCTAssertNil(BucketTagScanner.sensorID(inText: "penyu:sensor:"))
        XCTAssertNil(BucketTagScanner.sensorID(inText: ""))
    }

    /// A truncated UUID must not be padded or partially matched into a
    /// different, valid-looking id.
    func testRejectsATruncatedUUID() {
        XCTAssertNil(
            BucketTagScanner.sensorID(inText: "0F5D2C7A-1B44-4E90-9C11-A3F2E1C0")
        )
    }
}
