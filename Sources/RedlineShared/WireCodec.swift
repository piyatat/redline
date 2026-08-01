import Foundation

public enum WireCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(value)
        var length = UInt32(json.count).bigEndian
        var data = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        data.append(json)
        return data
    }

    public static func decodeOne<T: Decodable>(_ type: T.Type, from buffer: inout Data) throws -> T? {
        guard buffer.count >= 4 else { return nil }
        let length: UInt32 = buffer.prefix(4).withUnsafeBytes { raw in
            raw.load(as: UInt32.self).bigEndian
        }
        let total = Int(length) + 4
        guard buffer.count >= total else { return nil }
        let json = buffer.subdata(in: 4 ..< total)
        buffer.removeSubrange(0 ..< total)
        return try JSONDecoder().decode(T.self, from: json)
    }
}
