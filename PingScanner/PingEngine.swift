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
        await withCheckedContinuation { continuation in
            let gate = PingResumeGate(continuation: continuation)

            let pinger = SingleShotPinger(
                host: ip,
                ttl: settings.ttl,
                payloadSize: UInt(settings.packetSize),
                timeout: timeout
            ) { latencyMs in
                if let latencyMs {
                    gate.resume(returning: PingResult(ip: ip, latencyMs: latencyMs))
                } else {
                    gate.resume(returning: nil)
                }
            }
            pinger.start()

            // Страховка: если делегат/таймер потерялись — не зависаем на 0/N
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 1.0) {
                gate.resume(returning: nil)
            }
        }
    }
}

/// Гарантирует единственный resume continuation (thread-safe).
private final class PingResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<PingResult?, Never>

    init(continuation: CheckedContinuation<PingResult?, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: PingResult?) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(returning: value)
    }
}

private final class SingleShotPinger: NSObject, SimplePingDelegate {
    private let host: String
    private let ttl: UInt
    private let payloadSize: UInt
    private let timeout: TimeInterval
    private let completion: (Double?) -> Void
    private var ping: SimplePing?
    private var startedAt: Date?
    private var finished = false
    private var timeoutWork: DispatchWorkItem?
    /// Удерживаем себя до finish — иначе делегат умирает и скан залипает на 0/N
    private var selfRetain: SingleShotPinger?

    init(host: String, ttl: UInt, payloadSize: UInt, timeout: TimeInterval, completion: @escaping (Double?) -> Void) {
        self.host = host
        self.ttl = ttl
        self.payloadSize = payloadSize
        self.timeout = timeout
        self.completion = completion
    }

    func start() {
        selfRetain = self
        let p = SimplePing(hostName: host)
        p.delegate = self
        p.ttl = ttl
        p.payloadSize = payloadSize
        ping = p
        p.start()
    }

    private func finish(_ ms: Double?) {
        guard !finished else { return }
        finished = true
        timeoutWork?.cancel()
        ping?.stop()
        ping = nil
        completion(ms)
        selfRetain = nil
    }

    func simplePing(_ pinger: Any, didStartWithAddress address: Data) {
        startedAt = Date()
        (pinger as? SimplePing)?.send()

        let work = DispatchWorkItem { [weak self] in
            self?.finish(nil)
        }
        timeoutWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func simplePing(_ pinger: Any, didFailWithError error: Error) {
        finish(nil)
    }

    func simplePing(_ pinger: Any, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error) {
        finish(nil)
    }

    func simplePing(_ pinger: Any, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16) {
        let ms: Double
        if let startedAt {
            ms = Date().timeIntervalSince(startedAt) * 1000.0
        } else {
            ms = 0
        }
        finish(ms)
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