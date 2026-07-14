import Foundation

enum RangeParser {
    /// Поддержка: `111.88.x.x`, `111.88.1.x`, `111.88.1.1-111.88.1.50`
    static func ips(from pattern: String) throws -> [String] {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("-") {
            return try parseExplicitRange(trimmed)
        }
        return try parseWildcard(trimmed)
    }

    private static func parseWildcard(_ pattern: String) throws -> [String] {
        let parts = pattern.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            throw ParseError.invalidFormat
        }

        let octets = try parts.map { part -> OctetSpec in
            let s = String(part).lowercased()
            if s == "x" || s == "*" { return .any }
            guard let v = Int(s), (0...255).contains(v) else { throw ParseError.invalidOctet(s) }
            return .fixed(v)
        }

        var result: [String] = []
        result.reserveCapacity(65_000)

        let o1 = try expand(octets[0], defaultStart: 0, defaultEnd: 255)
        let o2 = try expand(octets[1], defaultStart: 0, defaultEnd: 255)
        let o3 = try expand(octets[2], defaultStart: 1, defaultEnd: 255)
        let o4 = try expand(octets[3], defaultStart: 1, defaultEnd: 255)

        for a in o1 {
            for b in o2 {
                for c in o3 {
                    for d in o4 {
                        result.append("\(a).\(b).\(c).\(d)")
                    }
                }
            }
        }
        return result
    }

    private static func parseExplicitRange(_ pattern: String) throws -> [String] {
        let chunks = pattern.split(separator: "-", maxSplits: 1).map(String.init)
        guard chunks.count == 2,
              let start = parseIP(chunks[0]),
              let end = parseIP(chunks[1]) else {
            throw ParseError.invalidFormat
        }
        let s = ipToUInt32(start)
        let e = ipToUInt32(end)
        guard s <= e else { throw ParseError.invalidRange }

        var out: [String] = []
        out.reserveCapacity(Int(e - s + 1))
        var cur = s
        while cur <= e {
            out.append(uint32ToIP(cur))
            cur += 1
        }
        return out
    }

    private static func expand(_ spec: OctetSpec, defaultStart: Int, defaultEnd: Int) throws -> [Int] {
        switch spec {
        case .fixed(let v):
            return [v]
        case .any:
            return Array(defaultStart...defaultEnd)
        }
    }

    private static func parseIP(_ s: String) -> (Int, Int, Int, Int)? {
        let p = s.trimmingCharacters(in: .whitespaces).split(separator: ".")
        guard p.count == 4,
              let a = Int(p[0]), let b = Int(p[1]), let c = Int(p[2]), let d = Int(p[3]),
              [a, b, c, d].allSatisfy({ (0...255).contains($0) }) else { return nil }
        return (a, b, c, d)
    }

    private static func ipToUInt32(_ ip: (Int, Int, Int, Int)) -> UInt32 {
        (UInt32(ip.0) << 24) | (UInt32(ip.1) << 16) | (UInt32(ip.2) << 8) | UInt32(ip.3)
    }

    private static func uint32ToIP(_ v: UInt32) -> String {
        let a = Int((v >> 24) & 255)
        let b = Int((v >> 16) & 255)
        let c = Int((v >> 8) & 255)
        let d = Int(v & 255)
        return "\(a).\(b).\(c).\(d)"
    }

    private enum OctetSpec {
        case fixed(Int)
        case any
    }

    enum ParseError: LocalizedError {
        case invalidFormat
        case invalidOctet(String)
        case invalidRange

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Формат: 111.88.x.x или 111.88.1.1-111.88.1.50"
            case .invalidOctet(let s):
                return "Некорректный октет: \(s)"
            case .invalidRange:
                return "Начальный IP больше конечного"
            }
        }
    }
}