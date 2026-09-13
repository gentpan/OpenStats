import Darwin
import Foundation

/// MaxMind DB（.mmdb）读取器，按格式规范 2.0 实现：二叉搜索树定位记录，再解码数据段。
/// 文件以内存映射方式打开，查询不需要把整个库读进内存。
public final class MaxMindDatabase: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable {
        case unreadable
        case missingMetadata
        case invalidMetadata(String)
        case corrupt
    }

    public let databaseType: String
    /// 数据生成时间
    public let buildDate: Date
    public let ipVersion: Int

    private let data: Data
    private let nodeCount: Int
    private let recordSize: Int
    private let treeSize: Int
    private let dataSectionStart: Int
    private let ipv4Start: Int

    private static let metadataMarker = Data([0xAB, 0xCD, 0xEF] + Array("MaxMind.com".utf8))

    public convenience init(url: URL) throws {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { throw Error.unreadable }
        try self.init(data: data)
    }

    public init(data: Data) throws {
        self.data = data
        // 元数据在文件末尾 128 KB 以内，取最后一次出现的标记
        let searchStart = max(0, data.count - 128 * 1024)
        guard let marker = data.range(of: Self.metadataMarker, options: .backwards, in: searchStart..<data.count) else {
            throw Error.missingMetadata
        }
        var decoder = Decoder(data: data, pointerBase: marker.upperBound)
        guard case .map(let metadata)? = try? decoder.decode(at: marker.upperBound).value else {
            throw Error.invalidMetadata("元数据不是字典")
        }
        guard let nodes = metadata["node_count"]?.integer, let record = metadata["record_size"]?.integer,
              [24, 28, 32].contains(record), let version = metadata["ip_version"]?.integer else {
            throw Error.invalidMetadata("缺少 node_count / record_size / ip_version")
        }
        nodeCount = nodes
        recordSize = record
        ipVersion = version
        databaseType = metadata["database_type"]?.string ?? ""
        buildDate = Date(timeIntervalSince1970: TimeInterval(metadata["build_epoch"]?.integer ?? 0))
        treeSize = (record * 2 / 8) * nodes
        dataSectionStart = treeSize + 16
        guard dataSectionStart <= data.count else { throw Error.corrupt }

        // IPv6 库里 IPv4 地址位于 ::/96 之下，预先走完前 96 个 0 位
        var node = 0
        if version == 6 {
            for _ in 0..<96 where node < nodes {
                node = Self.readRecord(data: data, node: node, bit: 0, recordSize: record)
            }
        }
        ipv4Start = node
    }

    /// 查询 IP，返回该地址对应的记录；不在库中时返回 nil
    public func lookup(_ address: String) -> Value? {
        guard let bytes = Self.addressBytes(address) else { return nil }
        if bytes.count == 16, ipVersion == 4 { return nil }

        var node = bytes.count == 4 ? ipv4Start : 0
        let bitCount = bytes.count * 8
        for index in 0..<bitCount {
            guard node < nodeCount else { break }
            let bit = Int((bytes[index >> 3] >> (7 - UInt8(index % 8))) & 1)
            node = Self.readRecord(data: data, node: node, bit: bit, recordSize: recordSize)
        }
        guard node > nodeCount else { return nil }   // 等于 nodeCount 表示没有数据
        let offset = node - nodeCount + treeSize
        guard offset < data.count else { return nil }
        var decoder = Decoder(data: data, pointerBase: dataSectionStart)
        return try? decoder.decode(at: offset).value
    }

    // MARK: 搜索树

    private static func readRecord(data: Data, node: Int, bit: Int, recordSize: Int) -> Int {
        data.withUnsafeBytes { raw -> Int in
            let bytes = raw.bindMemory(to: UInt8.self)
            func byte(_ offset: Int) -> Int { Int(bytes[offset]) }
            switch recordSize {
            case 24:
                let base = node * 6 + bit * 3
                return byte(base) << 16 | byte(base + 1) << 8 | byte(base + 2)
            case 28:
                let base = node * 7
                if bit == 0 {
                    return (byte(base + 3) & 0xF0) << 20 | byte(base) << 16 | byte(base + 1) << 8 | byte(base + 2)
                }
                return (byte(base + 3) & 0x0F) << 24 | byte(base + 4) << 16 | byte(base + 5) << 8 | byte(base + 6)
            default:
                let base = node * 8 + bit * 4
                return byte(base) << 24 | byte(base + 1) << 16 | byte(base + 2) << 8 | byte(base + 3)
            }
        }
    }

    static func addressBytes(_ address: String) -> [UInt8]? {
        var v4 = in_addr()
        if inet_pton(AF_INET, address, &v4) == 1 {
            return withUnsafeBytes(of: &v4.s_addr) { Array($0) }
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, address, &v6) == 1 {
            return withUnsafeBytes(of: &v6) { Array($0) }
        }
        return nil
    }

    // MARK: 数据段

    public indirect enum Value: Sendable, Equatable {
        case string(String)
        case double(Double)
        case bytes(Data)
        case unsigned(UInt64)
        case signed(Int64)
        case map([String: Value])
        case array([Value])
        case boolean(Bool)

        public subscript(key: String) -> Value? {
            if case .map(let map) = self { return map[key] }
            return nil
        }

        public var string: String? {
            if case .string(let value) = self { return value }
            return nil
        }

        public var integer: Int? {
            switch self {
            case .unsigned(let value): Int(exactly: value)
            case .signed(let value): Int(exactly: value)
            default: nil
            }
        }
    }

    struct Decoder {
        let data: Data
        let pointerBase: Int

        mutating func decode(at offset: Int) throws -> (value: Value, next: Int) {
            var position = offset
            let control = try byte(&position)
            var type = Int(control >> 5)

            if type == 1 {   // 指针：跳到数据段里的另一处解码，解码完回到指针之后
                let size = Int((control >> 3) & 0x3)
                let high = Int(control & 0x7)
                let raw = try bytes(&position, count: size + 1)
                var pointer: Int
                switch size {
                case 0: pointer = high << 8 | raw[0]
                case 1: pointer = (high << 16 | raw[0] << 8 | raw[1]) + 2048
                case 2: pointer = (high << 24 | raw[0] << 16 | raw[1] << 8 | raw[2]) + 526_336
                default: pointer = raw[0] << 24 | raw[1] << 16 | raw[2] << 8 | raw[3]
                }
                pointer += pointerBase
                let resolved = try decode(at: pointer)
                return (resolved.value, position)
            }
            if type == 0 {   // 扩展类型
                type = 7 + Int(try byte(&position))
            }

            var size = Int(control & 0x1F)
            if size >= 29 {
                let extra = try bytes(&position, count: size - 28)
                switch size {
                case 29: size = 29 + extra[0]
                case 30: size = 285 + (extra[0] << 8 | extra[1])
                default: size = 65_821 + (extra[0] << 16 | extra[1] << 8 | extra[2])
                }
            }

            switch type {
            case 2:
                let raw = try slice(&position, count: size)
                return (.string(String(decoding: raw, as: UTF8.self)), position)
            case 3:
                guard size == 8 else { throw Error.corrupt }
                let raw = try slice(&position, count: 8)
                return (.double(Double(bitPattern: UInt64(bigEndianBytes: raw))), position)
            case 4:
                return (.bytes(try slice(&position, count: size)), position)
            case 5, 6, 9, 10:
                let raw = try slice(&position, count: size)
                // uint128 超出 64 位的部分在地理库里用不到，只保留低 64 位
                return (.unsigned(UInt64(bigEndianBytes: raw.suffix(8))), position)
            case 7:
                var map: [String: Value] = [:]
                map.reserveCapacity(size)
                for _ in 0..<size {
                    let key = try decode(at: position)
                    guard case .string(let name) = key.value else { throw Error.corrupt }
                    let value = try decode(at: key.next)
                    map[name] = value.value
                    position = value.next
                }
                return (.map(map), position)
            case 8:
                let raw = try slice(&position, count: size)
                let unsigned = UInt32(truncatingIfNeeded: UInt64(bigEndianBytes: raw))
                return (.signed(Int64(Int32(bitPattern: unsigned))), position)
            case 11:
                var array: [Value] = []
                array.reserveCapacity(size)
                for _ in 0..<size {
                    let element = try decode(at: position)
                    array.append(element.value)
                    position = element.next
                }
                return (.array(array), position)
            case 14:
                return (.boolean(size != 0), position)
            case 15:
                guard size == 4 else { throw Error.corrupt }
                let raw = try slice(&position, count: 4)
                return (.double(Double(Float(bitPattern: UInt32(truncatingIfNeeded: UInt64(bigEndianBytes: raw))))), position)
            default:
                throw Error.corrupt
            }
        }

        private func byte(_ position: inout Int) throws -> UInt8 {
            guard position < data.count else { throw Error.corrupt }
            defer { position += 1 }
            return data[data.startIndex + position]
        }

        private func bytes(_ position: inout Int, count: Int) throws -> [Int] {
            try slice(&position, count: count).map(Int.init)
        }

        private func slice(_ position: inout Int, count: Int) throws -> Data {
            guard count >= 0, position + count <= data.count else { throw Error.corrupt }
            defer { position += count }
            return data.subdata(in: (data.startIndex + position)..<(data.startIndex + position + count))
        }
    }
}

private extension UInt64 {
    init<Bytes: Collection>(bigEndianBytes bytes: Bytes) where Bytes.Element == UInt8 {
        self = bytes.reduce(0) { $0 << 8 | UInt64($1) }
    }
}

// MARK: - 地理信息

/// 从 GeoLite2 City / Country 与 ASN 库里取出界面需要的字段
public struct GeoLocation: Sendable, Equatable {
    public var countryCode: String?
    public var countryName: String?
    public var city: String?
    public var asn: String?
    public var organization: String?
}

public enum GeoLookup {
    /// 名称优先取简体中文，没有时用英文
    public static func locate(_ address: String, location: MaxMindDatabase?, asn: MaxMindDatabase?) -> GeoLocation? {
        var result = GeoLocation()
        if let record = location?.lookup(address) {
            let country = record["country"] ?? record["registered_country"]
            result.countryCode = country?["iso_code"]?.string
            result.countryName = name(country)
            result.city = name(record["city"])
        }
        if let record = asn?.lookup(address) {
            result.asn = record["autonomous_system_number"]?.integer.map { "AS\($0)" }
            result.organization = record["autonomous_system_organization"]?.string
        }
        return result == GeoLocation() ? nil : result
    }

    private static func name(_ value: MaxMindDatabase.Value?) -> String? {
        guard let names = value?["names"] else { return nil }
        return names["zh-CN"]?.string ?? names["en"]?.string
    }
}
