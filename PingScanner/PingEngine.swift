import Foundation

struct PingSettings {
    var ttl: UInt = 64
    var timeoutMs: Int = 150
    var packetSize: Int = 56
    var maxConcurrent: Int = 48
}

struct PingResult: Identifiable, Hashable {
    let id = UUID()
    let ip: String
    let latencyMs: Double
}

@MainActor
final class PingScannerViewModel: NSObject, ObservableObject {
    @Published var pattern: String = "111.88.1.x"
    @Published var settings = PingSettings()
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var scannedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var alive: [PingResult] = []
    @Published var statusText: String = "Готов"
    @Published var errorText: String?

    private var scanTask: Task<Void, Never>?
    private let resultsStore = PingResultsStore()

    func startScan() {
        guard !isScanning else { return }
        errorText = nil
        alive = []
        progress = 0
        scannedCount = 0

        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.runScan()
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        statusText = "Остановлено"
    }

    func exportText() -> String {
        let header = "# LTE Ping Scan \(Date())\n# Pattern: \(pattern)\n# Alive: \(alive.count)\n"
        let body = alive.sorted { $0.ip < $1.ip }.map { "\($0.ip)\t\(String(format: "%.1f", $0.latencyMs))ms" }.joined(separator: "\n")
        return header + body + "\n"
    }

    private func runScan() async {
        isScanning = true
        statusText = "Разбор диапазона..."

        let ips: [String]
        do {
            ips = try RangeParser.ips(from: pattern)
        } catch {
            errorText = error.localizedDescription
            isScanning = false
            statusText = "Ошибка"
            return
        }

        totalCount = ips.count
        if totalCount > 80_000 {
            errorText = "Слишком большой диапазон (\(totalCount) IP). Сузьте маску, например 111.88.1.x"
            isScanning = false
            statusText = "Ошибка"
            return
        }

        statusText = "Сканирование \(totalCount) IP..."
        let timeout = TimeInterval(settings.timeoutMs) / 1000.0
        let maxConcurrent = max(1, min(settings.maxConcurrent, 128))

        await withTaskGroup(of: PingResult?.self) { group in
            var iterator = ips.makeIterator()
            var inFlight = 0
            var done = 0

            func enqueueNext() {
                while inFlight < maxConcurrent, let ip = iterator.next() {
                    if Task.isCancelled { return }
                    inFlight += 1
                    group.addTask {
                        await self.ping(ip: ip, timeout: timeout)
                    }
                }
            }

            enqueueNext()

            while inFlight > 0 {
                if Task.isCancelled { break }
                if let result = await group.next() {
                    inFlight -= 1
                    done += 1
                    if let result {
                        alive.append(result)
                        alive.sort { $0.ip < $1.ip }
                        resultsStore.append(result)
                    }
                    scannedCount = done
                    progress = totalCount == 0 ? 0 : Double(done) / Double(totalCount)
                    enqueueNext()
                }
            }
        }

        if Task.isCancelled {
            statusText = "Остановлено"
        } else {
            statusText = "Готово: ответили \(alive.count) из \(totalCount)"
        }
        isScanning = false
    }

    private func ping(ip: String, timeout: TimeInterval) async -> PingResult? {
        if let ms = await ICMPProbeEngine.ping(host: ip, settings: settings, timeout: timeout) {
            return PingResult(ip: ip, latencyMs: ms)
        }
        return nil
    }
}

/// Сохранение результатов в App Group (для обмена с другими приложениями)
final class PingResultsStore {
    private let suite = UserDefaults(suiteName: "group.27d6c67cc354451e.4")

    func append(_ result: PingResult) {
        var items = suite?.stringArray(forKey: "ping.alive") ?? []
        let line = "\(result.ip),\(result.latencyMs)"
        if !items.contains(line) {
            items.append(line)
            suite?.set(items, forKey: "ping.alive")
        }
    }

    func clear() {
        suite?.removeObject(forKey: "ping.alive")
    }
}