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
        let lock = NSLock()
        
        connection.stateUpdateHandler = { newState in
            lock.lock()
            if isFinished { lock.unlock(); return }
            switch newState {
            case .ready:
                isFinished = true
                lock.unlock()
                connection.cancel()
                continuation.resume(returning: true)
            case .failed(let error):
                print("Failed for port \(port): \(error)")
                isFinished = true
                lock.unlock()
                continuation.resume(returning: false)
            case .cancelled:
                isFinished = true
                lock.unlock()
                continuation.resume(returning: false)
            default:
                lock.unlock()
            }
        }
        connection.start(queue: DispatchQueue.global())
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            lock.lock()
            if isFinished { lock.unlock(); return }
            isFinished = true
            lock.unlock()
            print("Timeout for port \(port)")
            connection.cancel()
            continuation.resume(returning: false)
        }
    }
}

Task {
    print("Testing 41685:", await checkPort(host: "pixel-9-pro-xl", port: 41685))
    print("Testing 45147:", await checkPort(host: "pixel-9-pro-xl", port: 45147))
    print("Testing 30000:", await checkPort(host: "pixel-9-pro-xl", port: 30000))
    exit(0)
}
RunLoop.main.run()
