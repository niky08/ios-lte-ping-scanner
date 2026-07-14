import SwiftUI
import UIKit

private extension Color {
    static let oledBlack = Color(red: 0, green: 0, blue: 0)
    static let oledRow = Color(red: 0.11, green: 0.11, blue: 0.12)
}

struct ContentView: View {
    @StateObject private var vm = PingScannerViewModel()
    @FocusState private var isPatternFocused: Bool

    var body: some View {
        ZStack {
            Color.oledBlack
                .ignoresSafeArea()

            NavigationStack {
                Form {
                    Section("Диапазон") {
                        TextField("111.88.1.x", text: $vm.pattern)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isPatternFocused)
                        Text("x = 1…255. Пример: 111.88.1.x (~254 IP) или 111.88.x.x (~65k, долго)")
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
                    .listRowBackground(Color.oledRow)
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(Color.oledBlack)
                .navigationTitle("LTE Ping Scan")
                .toolbarBackground(Color.oledBlack, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Готово") { dismissKeyboard() }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .dismissKeyboardOnOLEDBackgroundTap()
        .onAppear { configureOLEDAppearance() }
    }

    private func dismissKeyboard() {
        isPatternFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func configureOLEDAppearance() {
        let black = UIColor.black
        UITableView.appearance().backgroundColor = black
        UICollectionView.appearance().backgroundColor = black
    }
}

// MARK: - Tap по чёрному фону (между секциями Form) закрывает клавиатуру

private struct OLEDBackgroundTapDismissKeyboard: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = PassthroughView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? PassthroughView else { return }
        view.coordinator = context.coordinator
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.installIfNeeded(on: window)
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private let gesture = UITapGestureRecognizer()

        override init() {
            super.init()
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            gesture.addTarget(self, action: #selector(dismissKeyboard))
        }

        func installIfNeeded(on window: UIWindow) {
            guard installedWindow !== window else { return }
            if let old = installedWindow {
                old.removeGestureRecognizer(gesture)
            }
            window.addGestureRecognizer(gesture)
            installedWindow = window
        }

        @objc private func dismissKeyboard() {
            installedWindow?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = touch.view else { return false }

            var v: UIView? = view
            while let current = v {
                if current is UIControl || current is UITextField || current is UITextView {
                    return false
                }
                v = current.superview
            }

            // Только пустое чёрное пространство: фон UITableView между карточками секций
            if let table = findTableView(from: view) {
                let point = touch.location(in: table)
                return table.indexPathForRow(at: point) == nil
            }

            // Safe area / корневой чёрный фон
            if view.backgroundColor == .black || view.backgroundColor == UIColor.black {
                return true
            }

            return false
        }

        private func findTableView(from view: UIView) -> UITableView? {
            var v: UIView? = view
            while let current = v {
                if let table = current as? UITableView { return table }
                v = current.superview
            }
            return nil
        }
    }

    /// Пропускает тапы к UI, но даёт coordinator доступ к window
    final class PassthroughView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window {
                coordinator?.installIfNeeded(on: window)
            }
        }
    }
}

private extension View {
    func dismissKeyboardOnOLEDBackgroundTap() -> some View {
        background(OLEDBackgroundTapDismissKeyboard())
    }
}

#Preview {
    ContentView()
}