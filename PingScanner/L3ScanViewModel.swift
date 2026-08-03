import Foundation
import SwiftUI

struct TCPScanSettings {
    var timeoutMs: Int = 1200
    var maxParallel: Int = 64
    var stage1Port: UInt16 = 443
}

@MainActor
final class L3ScanViewModel: ObservableObject {
    @Published var masterFile: L3MasterFile?
    @Published var settings = TCPScanSettings()
    @Published var isScanning = false
    @Published var stage: ScanStage = .idle
    @Published var progress: Double = 0
    @Published var scannedCount = 0
    @Published var totalCount = 0
    @Published var aliveHosts: [L3HostProbeResult] = []
    @Published var aliveEndpoints: [L3EndpointProbeResult] = []
    @Published var statusText = "Загрузка списка..."
    @Published var errorText: String?

    private var scanTask: Task<Void, Never>?
    private var sourceByTag: [String: L3Target] = [:]

    enum ScanStage: String {
        case idle
        case hosts
        case endpoints
        case done
    }

    init() {
        reloadBundled()
    }

    func reloadBundled() {
        do {
            let file = try L3TargetStore.loadBundled()
            apply(file)
        } catch {
            errorText = error.localizedDescription
            statusText = "Ошибка загрузки"
        }
    }

    func importFile(url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let file = try L3TargetStore.load(url: url)
            apply(file)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func apply(_ file: L3MasterFile) {
        masterFile = file
        sourceByTag = Dictionary(uniqueKeysWithValues: file.targets.map { ($0.tag, $0) })
        let hostCount = L3TargetStore.uniqueHosts(from: file).count
        statusText = "Готов: \(file.targets.count) endpoint, \(hostCount) host"
    }

    func startStage1() {
        guard let masterFile else { return }
        let hosts = L3TargetStore.uniqueHosts(from: masterFile)
        startScan(stage: .hosts, total: hosts.count) {
            self.aliveHosts = []
            let timeout = TimeInterval(self.settings.timeoutMs) / 1000.0
            self.aliveHosts = await TCPProbeEngine.scanHosts(
                hosts: hosts,
                port: self.settings.stage1Port,
                timeout: timeout,
                maxParallel: self.settings.maxParallel
            ) { done, total in
                self.scannedCount = done
                self.totalCount = total
                self.progress = total == 0 ? 0 : Double(done) / Double(total)
            }
            self.stage = .done
            self.statusText = "Этап 1: ответили \(self.aliveHosts.count) host на :\(self.settings.stage1Port)"
        }
    }

    func startStage2() {
        guard let masterFile else { return }
        let alive = Set(aliveHosts.map { $0.host.lowercased() })
        guard !alive.isEmpty else {
            errorText = "Сначала этап 1 — нужен список живых host"
            return
        }
        let targets = L3TargetStore.targets(from: masterFile, aliveHosts: alive)
        startScan(stage: .endpoints, total: targets.count) {
            self.aliveEndpoints = []
            let timeout = TimeInterval(self.settings.timeoutMs) / 1000.0
            self.aliveEndpoints = await TCPProbeEngine.scanEndpoints(
                targets: targets,
                timeout: timeout,
                maxParallel: self.settings.maxParallel
            ) { done, total in
                self.scannedCount = done
                self.totalCount = total
                self.progress = total == 0 ? 0 : Double(done) / Double(total)
            }
            self.stage = .done
            self.statusText = "Этап 2: ответили \(self.aliveEndpoints.count) endpoint"
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        statusText = "Остановлено"
    }

    func exportDocument() -> L3ScanExport {
        let aliveHostSet = Set(aliveHosts.map { $0.host.lowercased() })
        return L3ScanExport(
            scannedAt: ISO8601DateFormatter().string(from: Date()),
            network: "lte",
            stage1DefaultPort: Int(settings.stage1Port),
            aliveHosts: aliveHosts.map(\.exportRow),
            aliveEndpoints: aliveEndpoints.map { row in
                row.exportRow(source: sourceByTag[row.tag]?.source)
            },
            meta: .init(
                hostCount: aliveHosts.count,
                endpointCount: aliveEndpoints.count,
                sourceTargetCount: masterFile?.targets.filter { aliveHostSet.contains($0.host.lowercased()) }.count ?? 0
            )
        )
    }

    func exportJSONData() throws -> Data {
        try JSONEncoder().encode(exportDocument())
    }

    private func startScan(stage: ScanStage, total: Int, operation: @escaping () async -> Void) {
        guard !isScanning else { return }
        errorText = nil
        isScanning = true
        self.stage = stage
        scannedCount = 0
        totalCount = total
        progress = 0
        statusText = stage == .hosts ? "Этап 1: TCP host..." : "Этап 2: TCP host:port..."

        scanTask?.cancel()
        scanTask = Task {
            await operation()
            if Task.isCancelled {
                statusText = "Остановлено"
            }
            isScanning = false
        }
    }
}

struct L3ScanExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

import UniformTypeIdentifiers
