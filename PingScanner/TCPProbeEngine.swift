import Foundation
import Network

enum TCPProbeEngine {
    static func probe(host: String, port: UInt16, timeout: TimeInterval) async -> UInt16? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            let startedAt = Date()
            let connection = NWConnection(
                host: NWEndpoint.Host(trimmed),
                port: NWEndpoint.Port(integerLiteral: port),
                using: .tcp
            )
            let gate = ResumeGate(continuation: continuation)
            var timer: DispatchWorkItem?

            let finish: (UInt16?) -> Void = { value in
                timer?.cancel()
                connection.stateUpdateHandler = nil
                connection.cancel()
                gate.resume(returning: value)
            }

            let timeoutWork = DispatchWorkItem { finish(nil) }
            timer = timeoutWork
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let ms = min(UInt16.max, UInt16(Date().timeIntervalSince(startedAt) * 1000))
                    finish(ms)
                case .failed:
                    finish(nil)
                case .cancelled:
                    break
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))
        }
    }

    static func scanHosts(
        hosts: [String],
        port: UInt16,
        timeout: TimeInterval,
        maxParallel: Int,
        onProgress: @escaping @MainActor (Int, Int) -> Void
    ) async -> [L3HostProbeResult] {
        let parallel = min(max(maxParallel, 1), 128)
        var results: [L3HostProbeResult] = []
        let total = hosts.count

        await withTaskGroup(of: (String, UInt16?).self) { group in
            var iterator = hosts.makeIterator()
            var inFlight = 0
            var done = 0

            func spawnNext() {
                while inFlight < parallel, let host = iterator.next() {
                    inFlight += 1
                    group.addTask {
                        let ms = await probe(host: host, port: port, timeout: timeout)
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
                    results.append(L3HostProbeResult(id: host.lowercased(), host: host, port: port, latencyMs: ms))
                }
                await onProgress(done, total)
                spawnNext()
            }
        }

        return results.sorted { $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending }
    }

    static func scanEndpoints(
        targets: [L3Target],
        timeout: TimeInterval,
        maxParallel: Int,
        onProgress: @escaping @MainActor (Int, Int) -> Void
    ) async -> [L3EndpointProbeResult] {
        let parallel = min(max(maxParallel, 1), 128)
        var results: [L3EndpointProbeResult] = []
        let total = targets.count

        await withTaskGroup(of: (L3Target, UInt16?).self) { group in
            var iterator = targets.makeIterator()
            var inFlight = 0
            var done = 0

            func spawnNext() {
                while inFlight < parallel, let target = iterator.next() {
                    inFlight += 1
                    group.addTask {
                        let port = UInt16(clamping: target.port)
                        let ms = await probe(host: target.host, port: port, timeout: timeout)
                        return (target, ms)
                    }
                }
            }

            spawnNext()
            while inFlight > 0 {
                if Task.isCancelled { break }
                guard let (target, ms) = await group.next() else { break }
                inFlight -= 1
                done += 1
                if let ms {
                    results.append(
                        L3EndpointProbeResult(
                            id: target.tag,
                            tag: target.tag,
                            host: target.host,
                            port: UInt16(clamping: target.port),
                            latencyMs: ms
                        )
                    )
                }
                await onProgress(done, total)
                spawnNext()
            }
        }

        return results.sorted {
            if $0.latencyMs == $1.latencyMs { return $0.tag < $1.tag }
            return $0.latencyMs < $1.latencyMs
        }
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<UInt16?, Never>

    init(continuation: CheckedContinuation<UInt16?, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: UInt16?) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(returning: value)
    }
}

private extension UInt16 {
    init(clamping value: Int) {
        if value <= 0 {
            self = 0
        } else if value > Int(UInt16.max) {
            self = UInt16.max
        } else {
            self = UInt16(value)
        }
    }
}
