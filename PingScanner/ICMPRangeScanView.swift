import SwiftUI
import UIKit

struct ICMPRangeScanView: View {
    @StateObject private var vm = PingScannerViewModel()
    @FocusState private var isPatternFocused: Bool

    var body: some View {
        Form {
            Section("Диапазон") {
                TextField("111.88.1.x", text: $vm.pattern)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isPatternFocused)
                Text("x = 1…255. Пример: 111.88.1.x (~254 IP)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.oledRow)

            Section("ICMP") {
                Stepper("TTL: \(vm.settings.ttl)", value: $vm.settings.ttl, in: 1...255)
                Stepper("Timeout: \(vm.settings.timeoutMs) ms", value: $vm.settings.timeoutMs, in: 50...1000, step: 10)
                Stepper("Packet: \(vm.settings.packetSize) B", value: $vm.settings.packetSize, in: 32...512, step: 8)
                Stepper("Параллельно: \(vm.settings.maxConcurrent)", value: $vm.settings.maxConcurrent, in: 8...128, step: 8)
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

            Section {
                HStack {
                    Button(vm.isScanning ? "Стоп" : "Сканировать") {
                        dismissKeyboard()
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
            .listRowBackground(Color.oledRow)

            Section("Ответили (\(vm.alive.count))") {
                if vm.alive.isEmpty {
                    Text("Пока пусто").foregroundStyle(.secondary)
                } else {
                    ForEach(vm.alive) { item in
                        HStack {
                            Text(item.ip).font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(String(format: "%.0f ms", item.latencyMs)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listRowBackground(Color.oledRow)
        }
        .scrollContentBackground(.hidden)
        .background(Color(red: 0, green: 0, blue: 0))
    }

    private func dismissKeyboard() {
        isPatternFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private extension Color {
    static let oledRow = Color(red: 0.11, green: 0.11, blue: 0.12)
}
