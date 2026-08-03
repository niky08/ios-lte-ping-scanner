import SwiftUI
import UniformTypeIdentifiers

struct L3PoolScanView: View {
    @StateObject private var vm = L3ScanViewModel()
    @State private var showImporter = false
    @State private var exportDocument: L3ScanExportDocument?
    @State private var showExporter = false

    var body: some View {
        Form {
            Section("База WL+EU") {
                if let file = vm.masterFile {
                    Text("Endpoint: \(file.targets.count)")
                    Text("Уникальных host/domain: \(L3TargetStore.uniqueHosts(from: file).count)")
                    if let at = file.generatedAt {
                        Text("Собрано: \(at)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Импорт JSON") { showImporter = true }
            }
            .listRowBackground(Color.oledRow)

            Section("Этап 1 — ICMP") {
                Stepper("TTL: \(vm.settings.icmp.ttl)", value: $vm.settings.icmp.ttl, in: 1...255)
                Stepper("Timeout: \(vm.settings.icmp.timeoutMs) ms", value: $vm.settings.icmp.timeoutMs, in: 50...1000, step: 10)
                Stepper("Packet: \(vm.settings.icmp.packetSize) B", value: $vm.settings.icmp.packetSize, in: 32...512, step: 8)
                Stepper("Параллельно: \(vm.settings.icmp.maxConcurrent)", value: $vm.settings.icmp.maxConcurrent, in: 8...128, step: 8)
                Text("ICMP к каждому уникальному IP или domain (DNS резолвится автоматически).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.oledRow)

            Section("Этап 2 — TCP") {
                Stepper("Timeout: \(vm.settings.tcpTimeoutMs) ms", value: $vm.settings.tcpTimeoutMs, in: 300...3000, step: 100)
                Stepper("Параллельно: \(vm.settings.tcpParallel)", value: $vm.settings.tcpParallel, in: 8...128, step: 8)
                Text("TCP connect к host:port из тега — только для host/domain, прошедших ICMP.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.oledRow)

            Section("Статус") {
                Text(vm.statusText)
                if vm.isScanning {
                    ProgressView(value: vm.progress)
                    Text("\(vm.scannedCount) / \(vm.totalCount)")
                }
                if let err = vm.errorText {
                    Text(err).foregroundStyle(.red)
                }
            }
            .listRowBackground(Color.oledRow)

            Section("Скан") {
                HStack {
                    Button(vm.isScanning && vm.stage == .icmpHosts ? "Стоп" : "Этап 1: ICMP") {
                        vm.isScanning && vm.stage == .icmpHosts ? vm.stopScan() : vm.startStage1()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.masterFile == nil)

                    Button(vm.isScanning && vm.stage == .tcpEndpoints ? "Стоп" : "Этап 2: TCP") {
                        vm.isScanning && vm.stage == .tcpEndpoints ? vm.stopScan() : vm.startStage2()
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.masterFile == nil || vm.aliveHosts.isEmpty)
                }
            }
            .listRowBackground(Color.oledRow)

            Section("Экспорт") {
                Button("Экспорт JSON для сервера") {
                    do {
                        exportDocument = L3ScanExportDocument(data: try vm.exportJSONData())
                        showExporter = true
                    } catch {
                        vm.errorText = error.localizedDescription
                    }
                }
                .disabled(vm.aliveEndpoints.isEmpty)
            }
            .listRowBackground(Color.oledRow)

            Section("ICMP этап 1 (\(vm.aliveHosts.count))") {
                if vm.aliveHosts.isEmpty {
                    Text("Пусто").foregroundStyle(.secondary)
                } else {
                    ForEach(vm.aliveHosts.prefix(200)) { item in
                        HStack {
                            Text(item.host).font(.system(.body, design: .monospaced))
                            Spacer()
                            Text("\(item.latencyMs) ms").foregroundStyle(.secondary)
                        }
                    }
                    if vm.aliveHosts.count > 200 {
                        Text("… ещё \(vm.aliveHosts.count - 200)").foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(Color.oledRow)

            Section("TCP этап 2 (\(vm.aliveEndpoints.count))") {
                if vm.aliveEndpoints.isEmpty {
                    Text("Пусто").foregroundStyle(.secondary)
                } else {
                    ForEach(vm.aliveEndpoints.prefix(200)) { item in
                        HStack {
                            Text(item.tag).lineLimit(1)
                            Spacer()
                            Text("\(item.host):\(item.port) \(item.latencyMs)ms")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if vm.aliveEndpoints.count > 200 {
                        Text("… ещё \(vm.aliveEndpoints.count - 200)").foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(Color.oledRow)
        }
        .scrollContentBackground(.hidden)
        .background(Color.oledBlack)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result {
                vm.importFile(url: url)
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "l3-lte-scan-\(Int(Date().timeIntervalSince1970)).json"
        ) { _ in }
    }
}

private extension Color {
    static let oledRow = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let oledBlack = Color(red: 0, green: 0, blue: 0)
}
