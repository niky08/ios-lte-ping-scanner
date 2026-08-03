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
                    Text("Уникальных host: \(L3TargetStore.uniqueHosts(from: file).count)")
                    if let at = file.generatedAt {
                        Text("Собрано: \(at)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Импорт JSON") { showImporter = true }
            }
            .listRowBackground(Color.oledRow)

            Section("TCP") {
                Stepper("Timeout: \(vm.settings.timeoutMs) ms", value: $vm.settings.timeoutMs, in: 300...3000, step: 100)
                Stepper("Параллельно: \(vm.settings.maxParallel)", value: $vm.settings.maxParallel, in: 8...128, step: 8)
                Stepper("Этап 1 порт: \(vm.settings.stage1Port)", value: Binding(
                    get: { Int(vm.settings.stage1Port) },
                    set: { vm.settings.stage1Port = UInt16(clamping: $0) }
                ), in: 1...65535)
                Text("Этап 1 — TCP к host (domain/IP) на порту выше. Этап 2 — свой port у каждого тега.")
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
                    Button(vm.isScanning && vm.stage == .hosts ? "Стоп" : "Этап 1: host") {
                        vm.isScanning && vm.stage == .hosts ? vm.stopScan() : vm.startStage1()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.masterFile == nil)

                    Button(vm.isScanning && vm.stage == .endpoints ? "Стоп" : "Этап 2: port") {
                        vm.isScanning && vm.stage == .endpoints ? vm.stopScan() : vm.startStage2()
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

            Section("Host этап 1 (\(vm.aliveHosts.count))") {
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

            Section("Endpoint этап 2 (\(vm.aliveEndpoints.count))") {
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

private extension UInt16 {
    init(clamping value: Int) {
        if value <= 0 { self = 1 }
        else if value > Int(UInt16.max) { self = UInt16.max }
        else { self = UInt16(value) }
    }
}
