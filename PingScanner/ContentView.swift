import SwiftUI

struct ContentView: View {
    @StateObject private var vm = PingScannerViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Диапазон") {
                    TextField("111.88.x.x", text: $vm.pattern)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("x = 1…255. Пример: 111.88.1.x (~254 IP) или 111.88.x.x (~65k, долго)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("ICMP") {
                    Stepper("TTL: \(vm.settings.ttl)", value: $vm.settings.ttl, in: 1...255)
                    Stepper("Timeout: \(vm.settings.timeoutMs) ms", value: $vm.settings.timeoutMs, in: 50...1000, step: 10)
                    Stepper("Packet: \(vm.settings.packetSize) B", value: $vm.settings.packetSize, in: 32...512, step: 8)
                    Stepper("Параллельно: \(vm.settings.maxConcurrent)", value: $vm.settings.maxConcurrent, in: 8...128, step: 8)
                }

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

                Section {
                    HStack {
                        Button(vm.isScanning ? "Стоп" : "Сканировать") {
                            vm.isScanning ? vm.stopScan() : vm.startScan()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.pattern.trimmingCharacters(in: .whitespaces).isEmpty)

                        ShareLink(item: vm.exportText()) {
                            Label("Экспорт", systemImage: "square.and.arrow.up")
                        }
                        .disabled(vm.alive.isEmpty)
                    }
                }

                Section("Ответили (\(vm.alive.count))") {
                    if vm.alive.isEmpty {
                        Text("Пока пусто")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.alive) { item in
                            HStack {
                                Text(item.ip)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Text(String(format: "%.0f ms", item.latencyMs))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("LTE Ping Scan")
        }
    }
}

#Preview {
    ContentView()
}