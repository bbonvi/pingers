import XCTest
@testable import PingersLib

@MainActor
final class PingServiceTests: XCTestCase {
    var service: PingService!

    override func setUp() async throws {
        service = PingService()
    }

    func testParseLatencySuccess() {
        // Test standard macOS ping output
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=12.345 ms

        --- 1.1.1.1 ping statistics ---
        1 packets transmitted, 1 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 12.345/12.345/12.345/0.000 ms
        """

        let result = service.parseLatency(from: output)

        if case .success(let latency) = result {
            XCTAssertEqual(latency, 12.345, accuracy: 0.001)
        } else {
            XCTFail("Expected success result, got \(result)")
        }
    }

    func testParseLatencyWholeNumber() {
        // Test ping output with whole number latency
        let output = """
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=42 ms
        """

        let result = service.parseLatency(from: output)

        if case .success(let latency) = result {
            XCTAssertEqual(latency, 42.0, accuracy: 0.001)
        } else {
            XCTFail("Expected success result, got \(result)")
        }
    }

    func testParseLatencyHighPrecision() {
        // Test ping output with high precision
        let output = """
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=0.123 ms
        """

        let result = service.parseLatency(from: output)

        if case .success(let latency) = result {
            XCTAssertEqual(latency, 0.123, accuracy: 0.0001)
        } else {
            XCTFail("Expected success result, got \(result)")
        }
    }

    func testParseLatencyMalformed() {
        // Test malformed output without time field
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        Request timeout for icmp_seq 0
        """

        let result = service.parseLatency(from: output)

        if case .commandFailed(let reason) = result {
            XCTAssertTrue(reason.contains("Failed to parse"))
        } else {
            XCTFail("Expected commandFailed result, got \(result)")
        }
    }

    func testParseLatencyEmpty() {
        // Test empty output
        let output = ""

        let result = service.parseLatency(from: output)

        if case .commandFailed(let reason) = result {
            XCTAssertTrue(reason.contains("Failed to parse"))
        } else {
            XCTFail("Expected commandFailed result, got \(result)")
        }
    }

    func testParseLatencyInvalidNumber() {
        // Test output with non-numeric time value (edge case)
        let output = "time=invalid ms"

        let result = service.parseLatency(from: output)

        if case .commandFailed(let reason) = result {
            XCTAssertTrue(reason.contains("parse") || reason.contains("Invalid"))
        } else {
            XCTFail("Expected commandFailed result, got \(result)")
        }
    }

    func testPingResultIsOnline() {
        // Test isOnline property
        XCTAssertTrue(PingResult.success(latencyMs: 10.0).isOnline)
        XCTAssertFalse(PingResult.timeout.isOnline)
        XCTAssertFalse(PingResult.networkUnreachable.isOnline)
        XCTAssertFalse(PingResult.commandFailed(reason: "error").isOnline)
    }

    func testPingResultEquality() {
        // Test Equatable conformance
        XCTAssertEqual(
            PingResult.success(latencyMs: 10.0),
            PingResult.success(latencyMs: 10.0)
        )
        XCTAssertNotEqual(
            PingResult.success(latencyMs: 10.0),
            PingResult.success(latencyMs: 20.0)
        )
        XCTAssertEqual(PingResult.timeout, PingResult.timeout)
        XCTAssertEqual(
            PingResult.commandFailed(reason: "test"),
            PingResult.commandFailed(reason: "test")
        )
    }
}
