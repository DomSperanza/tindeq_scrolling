import Foundation

/// Tindeq Progressor GATT protocol. Mirrors `app/.../ble/TindeqProtocol.kt` and
/// `tindeq-sdk/src/protocol.ts`.
public enum TindeqProtocol {
    public static let serviceUUID = "7e4e1701-1ea6-40c9-9dcc-13d34ffead57"
    public static let writeUUID = "7e4e1703-1ea6-40c9-9dcc-13d34ffead57"
    public static let notifyUUID = "7e4e1702-1ea6-40c9-9dcc-13d34ffead57"

    public static let namePrefixes = ["Progressor", "Tindeq", "TINDEQ"]

    public static let responseCmd: UInt8 = 0
    public static let responseWeight: UInt8 = 1
    public static let responseLowPower: UInt8 = 4

    public static let cmdTareScale: UInt8 = 0x64
    public static let cmdStartWeightMeas: UInt8 = 0x65
    public static let cmdStopWeightMeas: UInt8 = 0x66
    public static let cmdSleep: UInt8 = 0x6e

    public struct WeightSample: Equatable, Sendable {
        public let weight: Float
        public let useconds: UInt32

        public init(weight: Float, useconds: UInt32) {
            self.weight = weight
            self.useconds = useconds
        }
    }

    /// TLV command: tag (opcode) + length 0 for commands without a value payload.
    public static func packCmd(_ cmd: UInt8) -> Data {
        Data([cmd, 0])
    }

    /// Parses a notification from the data characteristic into its kind byte and any
    /// weight samples (little-endian float32 weight + uint32 microseconds, 8 bytes each).
    public static func parseNotifyPayload(_ data: Data) -> (kind: UInt8, samples: [WeightSample]) {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return (0, []) }
        let kind = bytes[0]
        let payloadSize = Int(bytes[1])
        let end = min(2 + payloadSize, bytes.count)
        var samples: [WeightSample] = []
        var offset = 2
        while offset + 8 <= end {
            let weightBits = readUInt32LE(bytes, offset)
            let useconds = readUInt32LE(bytes, offset + 4)
            samples.append(WeightSample(weight: Float(bitPattern: weightBits), useconds: useconds))
            offset += 8
        }
        return (kind, samples)
    }

    public static func isProgressorName(_ name: String?) -> Bool {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return namePrefixes.contains { name.hasPrefix($0) }
    }

    private static func readUInt32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}
