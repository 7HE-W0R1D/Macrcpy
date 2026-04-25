import Foundation
import Network

func checkPort(host: String, port: UInt16) async -> Bool {
    return await withCheckedContinuation { continuation in
        let hostEndpoint = NWEndpoint.Host(host)
        guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
            continuation.resume(returning: false)
            return
        }
        let connection = NWConnection(host: hostEndpoint, port: portEndpoint, using: .tcp)
        
        var isFinished = false
        connection.stateUpdateHandler = { state in
            guard !isFinished else { return }
            switch state {
            case .ready:
                isFinished = true
                connection.cancel()
                continuation.resume(returning: true)
            case .failed(_), .cancelled:
                isFinished = true
                continuation.resume(returning: false)
            default:
                break
            }
        }
        
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            if !isFinished {
                isFinished = true
                connection.cancel()
                continuation.resume(returning: false)
            }
        }
    }
}

func scanPorts(host: String, range: ClosedRange<UInt16>, maxConcurrency: Int = 100) async -> [UInt16] {
    var openPorts: [UInt16] = []
    
    await withTaskGroup(of: (UInt16, Bool).self) { group in
        var index = range.lowerBound
        
        for _ in 0..<min(maxConcurrency, range.count) {
            let port = index
            group.addTask { return (port, await checkPort(host: host, port: port)) }
            if index == range.upperBound { break }
            index += 1
        }
        
        for await (port, isOpen) in group {
            if isOpen {
                openPorts.append(port)
                if openPorts.count >= 2 {
                    group.cancelAll()
                    break
                }
            }
            
            if index <= range.upperBound, !group.isCancelled {
                let port = index
                group.addTask { return (port, await checkPort(host: host, port: port)) }
                index += 1
            }
        }
    }
    return openPorts.sorted()
}

Task {
    print("Starting scan...")
    let start = Date()
    let ports = await scanPorts(host: "127.0.0.1", range: 1...10000, maxConcurrency: 500)
    print("Found ports: \(ports) in \(Date().timeIntervalSince(start))s")
    exit(0)
}

RunLoop.main.run()
