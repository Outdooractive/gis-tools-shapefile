import Foundation

// MARK: - Little- and big-endian helpers

extension Data {

    // MARK: - Writing

    mutating func appendBigEndian(_ value: Int32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: Int32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: Double) {
        let bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: bits) { append(contentsOf: $0) }
    }

    // MARK: - Reading

    func readByte(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < count else { return nil }

        return self[startIndex + offset]
    }

    func readBigEndianInt32(at offset: Int) -> Int32? {
        guard offset >= 0, offset + 4 <= count else { return nil }

        return withUnsafeBytes {
            Int32(bigEndian: $0.loadUnaligned(fromByteOffset: offset, as: Int32.self))
        }
    }

    func readLittleEndianInt32(at offset: Int) -> Int32? {
        guard offset >= 0, offset + 4 <= count else { return nil }

        return withUnsafeBytes {
            Int32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: Int32.self))
        }
    }

    func readLittleEndianUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }

        return withUnsafeBytes {
            UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
        }
    }

    func readLittleEndianDouble(at offset: Int) -> Double? {
        guard offset >= 0, offset + 8 <= count else { return nil }

        return withUnsafeBytes {
            Double(bitPattern: UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)))
        }
    }

}
