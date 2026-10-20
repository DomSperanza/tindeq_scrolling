import XCTest
@testable import TindeqCore

final class TindeqProtocolTests: XCTestCase {
    private func sampleBytes(weight: Float, useconds: UInt32) -> [UInt8] {
        let w = weight.bitPattern
        return [
            UInt8(w & 0xff), UInt8((w >> 8) & 0xff), UInt8((w >> 16) & 0xff), UInt8(w >> 24),
            UInt8(useconds & 0xff), UInt8((useconds >> 8) & 0xff),
            UInt8((useconds >> 16) & 0xff), UInt8(useconds >> 24),
        ]
    }

    func testPackCmd() {
        XCTAssertEqual(TindeqProtocol.packCmd(TindeqProtocol.cmdStartWeightMeas), Data([0x65, 0]))
    }

    func testParsesWeightSamples() {
        var bytes: [UInt8] = [TindeqProtocol.responseWeight, 16]
        bytes += sampleBytes(weight: 12.5, useconds: 1_000_000)
        bytes += sampleBytes(weight: -0.25, useconds: 0xfffffff0)
        let (kind, samples) = TindeqProtocol.parseNotifyPayload(Data(bytes))
        XCTAssertEqual(kind, TindeqProtocol.responseWeight)
        XCTAssertEqual(samples, [
            .init(weight: 12.5, useconds: 1_000_000),
            .init(weight: -0.25, useconds: 0xfffffff0),
        ])
    }

    func testRespectsDeclaredPayloadSize() {
        var bytes: [UInt8] = [TindeqProtocol.responseWeight, 8]
        bytes += sampleBytes(weight: 1, useconds: 1)
        bytes += sampleBytes(weight: 2, useconds: 2)
        XCTAssertEqual(TindeqProtocol.parseNotifyPayload(Data(bytes)).samples.count, 1)
    }

    func testIgnoresTruncatedSample() {
        var bytes: [UInt8] = [TindeqProtocol.responseWeight, 16]
        bytes += sampleBytes(weight: 1, useconds: 1)
        bytes += [0, 0, 0]
        XCTAssertEqual(TindeqProtocol.parseNotifyPayload(Data(bytes)).samples.count, 1)
    }

    func testShortPayload() {
        let (kind, samples) = TindeqProtocol.parseNotifyPayload(Data([1]))
        XCTAssertEqual(kind, 0)
        XCTAssertTrue(samples.isEmpty)
    }

    func testParsesFromSlicedData() {
        // CoreBluetooth can hand back Data slices with a non-zero startIndex.
        var bytes: [UInt8] = [0xAA, TindeqProtocol.responseWeight, 8]
        bytes += sampleBytes(weight: 3, useconds: 7)
        let slice = Data(bytes).dropFirst()
        XCTAssertEqual(TindeqProtocol.parseNotifyPayload(slice).samples, [.init(weight: 3, useconds: 7)])
    }

    func testProgressorNames() {
        XCTAssertTrue(TindeqProtocol.isProgressorName("Progressor_1234"))
        XCTAssertTrue(TindeqProtocol.isProgressorName("TINDEQ"))
        XCTAssertFalse(TindeqProtocol.isProgressorName("AirPods"))
        XCTAssertFalse(TindeqProtocol.isProgressorName(nil))
        XCTAssertFalse(TindeqProtocol.isProgressorName("  "))
    }
}
