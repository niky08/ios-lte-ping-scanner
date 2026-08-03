import Foundation

enum L3TargetStore {
    static let bundleName = "l3_master_targets"

    static func loadBundled() throws -> L3MasterFile {
        guard let url = Bundle.main.url(forResource: bundleName, withExtension: "json") else {
            throw L3TargetError.missingBundle
        }
        return try load(url: url)
    }

    static func load(url: URL) throws -> L3MasterFile {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(L3MasterFile.self, from: data)
        return sanitize(decoded)
    }

    static func uniqueHosts(from file: L3MasterFile) -> [String] {
        if let hosts = file.hosts, !hosts.isEmpty {
            return hosts.map(\.host).filter(isValidHost)
        }
        var seen = Set<String>()
        var out: [String] = []
        for target in file.targets where isValidHost(target.host) {
            let key = target.host.lowercased()
            if seen.insert(key).inserted {
                out.append(target.host)
            }
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func targets(from file: L3MasterFile, aliveHosts: Set<String>) -> [L3Target] {
        let alive = Set(aliveHosts.map { $0.lowercased() })
        return file.targets.filter { alive.contains($0.host.lowercased()) }
    }

    private static func sanitize(_ file: L3MasterFile) -> L3MasterFile {
        var copy = file
        copy.targets = file.targets.filter { isValidHost($0.host) && $0.port > 0 && $0.port <= 65535 }
        copy.hosts = uniqueHosts(from: copy).map(L3HostEntry.init(host:))
        return copy
    }

    private static func isValidHost(_ host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 253 else { return false }
        let lower = trimmed.lowercased()
        if lower == "0.0.0.0" || lower == "localhost" || lower.hasPrefix("127.") {
            return false
        }
        if trimmed.contains(" ") || trimmed.contains("\n") {
            return false
        }
        return true
    }
}

enum L3TargetError: LocalizedError {
    case missingBundle

    var errorDescription: String? {
        switch self {
        case .missingBundle:
            return "Не найден l3_master_targets.json в бандле"
        }
    }
}
