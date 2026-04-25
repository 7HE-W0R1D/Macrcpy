import Foundation
import Network

class PortScanner {
    private class ScanState: @unchecked Sendable {
        var isFinished = false
        let lock = NSLock()
    }

    func scanPortsNatively(host: String, range: ClosedRange<UInt16>, maxConcurrency: Int) async -> [UInt16] {
        var openPorts: [UInt16] = []
        var totalScanned = 0
        
        await withTaskGroup(of: (UInt16, Bool).self) { group in
            var index = range.lowerBound
            
            for _ in 0..<min(maxConcurrency, range.count) {
                let port = index
                group.addTask { return (port, await self.checkPort(host: host, port: port)) }
                if index == range.upperBound { break }
                index += 1
            }
            
            for await (port, isOpen) in group {
                totalScanned += 1
                if isOpen {
                    openPorts.append(port)
                    print("Found open port: \(port)")
                    if openPorts.count >= 2 {
                        group.cancelAll()
                        break
                    }
                }
                
                if index <= range.upperBound, !group.isCancelled {
                    let port = index
                    group.addTask { return (port, await self.checkPort(host: host, port: port)) }
                    index += 1
                }
            }
        }
        print("Total scanned: \(totalScanned)")
        return openPorts.sorted()
    }

    private func checkPort(host: String, port: UInt16) async -> Bool {
        return await withCheckedContinuation { continuation in
            let hostEndpoint = NWEndpoint.Host(host)
            guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: false)
                return
            }
            let connection = NWConnection(host: hostEndpoint, port: portEndpoint, using: .tcp)
            
            let state = ScanState()
            
            connection.stateUpdateHandler = { newState in
                state.lock.lock()
                if state.isFinished {
                    state.lock.unlock()
                    return
                }
                switch newState {
                case .ready:
                    state.isFinished = true
                    state.lock.unlock()
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed(let error):
                    state.isFinished = true
                    state.lock.unlock()
                    continuation.resume(returning: false)
                case .cancelled:
                    state.isFinished = true
                    state.lock.unlock()
                    continuation.resume(returning: false)
                default:
                    state.lock.unlock()
                }
            }
            
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                state.lock.lock()
                if state.isFinished {
                    state.lock.unlock()
                    return
                }
                state.isFinished = true
                state.lock.unlock()
                connection.cancel()
                continuation.resume(returning: false)
            }
        }
    }
}

let scanner = PortScanner()
let host = "pixel-9-pro-xl"

Task {
    print("Starting scan on \(host) for ports 30000...49999")
    let start = Date()
    let openPorts = await scanner.scanPortsNatively(host: host, range: 30000...49999, maxConcurrency: 100)
    let duration = Date().timeIntervalSince(start)
    print("Scan completed in \(String(format: "%.2f", duration)) seconds.")
    print("Open ports found: \(openPorts)")
    exit(0)
}

RunLoop.main.run()
