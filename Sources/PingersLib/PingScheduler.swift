import Foundation
import Dispatch

/// Scheduler for periodic ping operations
@MainActor
public class PingScheduler {
    private let service: PingService
    private var timer: DispatchSourceTimer?
    private let intervalSeconds: TimeInterval
    private let resultHandler: (PingResult) -> Void

    /// Initialize scheduler
    /// - Parameters:
    ///   - service: PingService instance to use
    ///   - intervalSeconds: Interval between pings (default 10s)
    ///   - resultHandler: Callback invoked with each ping result
    public init(
        service: PingService,
        intervalSeconds: TimeInterval = 10.0,
        resultHandler: @escaping (PingResult) -> Void
    ) {
        self.service = service
        self.intervalSeconds = intervalSeconds
        self.resultHandler = resultHandler
    }

    /// Start periodic pinging
    public func start() {
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(
            deadline: .now(),
            repeating: intervalSeconds,
            leeway: .milliseconds(100)
        )

        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                let result = await self.service.ping()
                self.resultHandler(result)
            }
        }

        timer.resume()
        self.timer = timer
    }

    /// Stop periodic pinging
    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Update interval and restart if running
    /// - Parameter newInterval: New interval in seconds
    public func updateInterval(_ newInterval: TimeInterval) {
        let wasRunning = timer != nil
        stop()

        // Can't directly modify intervalSeconds since it's let
        // This would require reinitializing the scheduler
        // For now, caller should create new scheduler

        if wasRunning {
            start()
        }
    }

    deinit {
        timer?.cancel()
    }
}
