import Foundation

/// ICMP echo to host/IP/domain (SimplePing resolves DNS for domains).
enum ICMPProbeEngine {
    static func scanHosts(
        hosts: [String],
        settings: PingSettings,
        onProgress: @escaping @MainActor (Int, Int) -> Void
    ) async -> [L3HostProbeResult] {
        let timeout = TimeInterval(settings.timeoutMs) / 1000.0
        let parallel = max(1, min(settings.maxConcurrent, 128))
        var results: [L3HostProbeResult] = []
        let total = hosts.count

        await withTaskGroup(of: (String, Double?).self) { group in
            var iterator = hosts.makeIterator()
            var inFlight = 0
            var done = 0

            func spawnNext() {
                while inFlight < parallel, let host = iterator.next() {
                    if Task.isCancelled { return }
                    inFlight += 1
                    group.addTask {
                        let ms = await ping(host: host, settings: settings, timeout: timeout)
                        return (host, ms)
                    }
                }
            }

            spawnNext()
            while inFlight > 0 {
                if Task.isCancelled { break }
                guard let (host, ms) = await group.next() else { break }
                inFlight -= 1
                done += 1
                if let ms {
                    results.append(
                        L3HostProbeResult(
                            id: host.lowercased(),
                            host: host,
                            port: 0,
                            latencyMs: UInt16(min(ms, Double(UInt16.max)))
                        )
                    )
                }
                await onProgress(done, total)
                spawnNext()
            }
        }

        return results.sorted {
            $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending
        }
    }

    static func ping(host: String, settings: PingSettings, timeout: TimeInterval) async -> Double? {
        await withCheckedContinuation { continuation in
            let gate = PingResumeGate(continuation: continuation)
            let pinger = SingleShotPinger(
                host: host,
                ttl: settings.ttl,
                payloadSize: UInt(settings.packetSize),
                timeout: timeout
            ) { latencyMs in
                gate.resume(returning: latencyMs)
            }
            pinger.start()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 1.0) {
                gate.resume(returning: nil)
            }
        }
    }
}

/// Гарантирует единственный resume continuation (thread-safe).
final class PingResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<Double?, Never>

    init(continuation: CheckedContinuation<Double?, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Double?) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(returning: value)
    }
}

final class SingleShotPinger: NSObject, SimplePingDelegate {
    private let host: String
    private let ttl: UInt
    private let payloadSize: UInt
    private let timeout: TimeInterval
    private let completion: (Double?) -> Void
    private var ping: SimplePing?
    private var startedAt: Date?
    private var finished = false
    private var timeoutWork: DispatchWorkItem?
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
