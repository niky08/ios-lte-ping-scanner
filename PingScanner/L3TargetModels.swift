import Foundation

struct L3MasterFile: Codable {
    var version: Int
    var generatedAt: String?
    var sourceFiles: Int?
    var targetCount: Int?
    var uniqueHosts: Int?
    var uniqueHostPorts: Int?
    var hosts: [L3HostEntry]?
    var targets: [L3Target]

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case sourceFiles = "source_files"
        case targetCount = "target_count"
        case uniqueHosts = "unique_hosts"
        case uniqueHostPorts = "unique_host_ports"
        case hosts
        case targets
    }
}

struct L3HostEntry: Codable, Hashable {
    var host: String
}

struct L3Target: Codable, Hashable, Identifiable {
    var tag: String
    var host: String
    var port: Int
    var source: String?

    var id: String { tag }

    var hostPortKey: String {
        "\(host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(port)"
    }
}

struct L3HostProbeResult: Identifiable, Hashable {
    let id: String
    let host: String
    let port: UInt16
    let latencyMs: UInt16
}

struct L3EndpointProbeResult: Identifiable, Hashable {
    let id: String
    let tag: String
    let host: String
    let port: UInt16
    let latencyMs: UInt16
}

struct L3ScanExport: Codable {
    var version: Int = 1
    var scannedAt: String
    var network: String
    var stage1Method: String
    var aliveHosts: [L3HostProbeResult.ExportRow]
    var aliveEndpoints: [L3EndpointProbeResult.ExportRow]

    struct Meta: Codable {
        var hostCount: Int
        var endpointCount: Int
        var sourceTargetCount: Int
    }

    var meta: Meta
}

extension L3HostProbeResult {
    struct ExportRow: Codable, Hashable {
        var host: String
        var latencyMs: Int
        var method: String
    }

    var exportRow: ExportRow {
        ExportRow(host: host, latencyMs: Int(latencyMs), method: "icmp")
    }
}

extension L3EndpointProbeResult {
    struct ExportRow: Codable, Hashable {
        var tag: String
        var host: String
        var port: Int
        var latencyMs: Int
        var source: String?
    }

    func exportRow(source: String?) -> ExportRow {
        ExportRow(tag: tag, host: host, port: Int(port), latencyMs: Int(latencyMs), source: source)
    }
}
