import Foundation

/// Result of a ping operation
public enum PingResult: Equatable {
    case success(latencyMs: Double)
    case timeout
    case networkUnreachable
    case commandFailed(reason: String)

    public var isOnline: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

/// Service for executing ping commands and parsing results
@MainActor
public class PingService {
    private let host: String
    private let timeoutMs: Int

    public init(host: String = "1.1.1.1", timeoutMs: Int = 2000) {
        self.host = host
        self.timeoutMs = timeoutMs
    }

    /// Execute ping and return result
    /// - Returns: PingResult indicating success with latency or failure reason
    public func ping() async -> PingResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")

        // -c 1: send 1 packet
        // -W timeout: wait time in milliseconds
        process.arguments = ["-c", "1", "-W", "\(timeoutMs)", host]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            // Wait with timeout
            let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0 + 1.0)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            if process.isRunning {
                process.terminate()
                return .timeout
            }

            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            // Check exit status
            let exitCode = process.terminationStatus

            if exitCode == 0 {
                // Success - parse latency
                return parseLatency(from: output)
            } else if exitCode == 2 {
                // Network unreachable or no route to host
                return .networkUnreachable
            } else {
                // Other failure
                let reason = errorOutput.isEmpty ? "Exit code \(exitCode)" : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                return .commandFailed(reason: reason)
            }

        } catch {
            return .commandFailed(reason: error.localizedDescription)
        }
    }

    /// Parse latency from ping output
    /// - Parameter output: Raw ping output string
    /// - Returns: PingResult with latency or failure
    public func parseLatency(from output: String) -> PingResult {
        // macOS ping output format: "time=12.345 ms"
        let pattern = #"time=(\d+\.?\d*)\s*ms"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: output, options: [], range: NSRange(output.startIndex..., in: output)),
              let latencyRange = Range(match.range(at: 1), in: output) else {
            return .commandFailed(reason: "Failed to parse latency from output")
        }

        let latencyString = String(output[latencyRange])
        guard let latency = Double(latencyString) else {
            return .commandFailed(reason: "Invalid latency value")
        }

        return .success(latencyMs: latency)
    }
}
