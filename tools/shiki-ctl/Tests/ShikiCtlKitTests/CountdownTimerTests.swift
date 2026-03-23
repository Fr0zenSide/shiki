import Foundation
import Testing
@testable import ShikiCtlKit

/// Mock key reader that returns pre-configured key events at specific tick counts.
final class MockKeyReader: KeyReading, @unchecked Sendable {
    var escapeAtTick: Int?
    private var currentTick: Int = 0

    init(escapeAtTick: Int? = nil) {
        self.escapeAtTick = escapeAtTick
    }

    func readKeyWithTimeout(ms: Int) -> KeyEvent? {
        guard let escapeTick = escapeAtTick else { return nil }
        if currentTick == escapeTick { return .escape }
        return nil
    }

    func setCurrentTick(_ tick: Int) {
        currentTick = tick
    }
}

/// Thread-safe tick collector for Sendable closures.
final class TickCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Int] = []

    func append(_ value: Int) {
        lock.lock()
        _values.append(value)
        lock.unlock()
    }

    var values: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }
}

@Suite("CountdownTimer — BR-13 to BR-18")
struct CountdownTimerTests {

    // BR-14: countdown 0 → immediate
    @Test("Countdown 0 returns immediate")
    func stop_countdownZero_stopsImmediately() async {
        let timer = CountdownTimer(isInteractive: false, keyReader: nil, onTick: { _ in })
        let result = await timer.run(seconds: 0)
        #expect(result == .immediate)
    }

    // BR-13: Negative clamped to 0
    @Test("Negative countdown clamped to 0 → immediate")
    func stop_countdownNegative_clampedToZero() async {
        let timer = CountdownTimer(isInteractive: false, keyReader: nil, onTick: { _ in })
        let result = await timer.run(seconds: -5)
        #expect(result == .immediate)
    }

    // BR-13: Clamped to 60 max
    @Test("Countdown clamped to 60 max")
    func stop_countdownClampedToSixtyMaximum() {
        #expect(CountdownTimer.clampSeconds(61) == 60)
        #expect(CountdownTimer.clampSeconds(100) == 60)
        #expect(CountdownTimer.clampSeconds(-1) == 0)
    }

    // BR-15: tick handler called with remaining values
    @Test("Tick handler called with correct remaining values")
    func stop_eachTickShowsSaveDescription() async {
        let collector = TickCollector()
        let timer = CountdownTimer(isInteractive: false, keyReader: nil, onTick: { remaining in
            collector.append(remaining)
        }, sleepDuration: .zero)

        let result = await timer.run(seconds: 3)
        #expect(result == .completed)
        #expect(collector.values == [3, 2, 1])
    }

    // BR-16: Esc cancels → .cancelled
    @Test("Esc key press cancels and returns cancelled")
    func stop_escKeyPress_cancelsAndReturnsToRunning() async {
        let mockReader = MockKeyReader(escapeAtTick: 2)
        let collector = TickCollector()
        let timer = CountdownTimer(isInteractive: true, keyReader: mockReader, onTick: { remaining in
            collector.append(remaining)
            mockReader.setCurrentTick(remaining)
        }, sleepDuration: .zero)

        let result = await timer.run(seconds: 3)
        #expect(result == .cancelled)
        #expect(collector.values.first == 3)
    }

    // BR-17: non-TTY disables Esc
    @Test("Non-TTY mode ignores key input, completes normally")
    func stop_nonTTY_disablesEscCancel() async {
        let mockReader = MockKeyReader(escapeAtTick: 2)
        let collector = TickCollector()
        let timer = CountdownTimer(isInteractive: false, keyReader: mockReader, onTick: { remaining in
            collector.append(remaining)
        }, sleepDuration: .zero)

        let result = await timer.run(seconds: 3)
        #expect(result == .completed)
        #expect(collector.values == [3, 2, 1])
    }

    // Full countdown completes
    @Test("Full countdown with no Esc returns completed")
    func stop_fullCountdown_completesNormally() async {
        let mockReader = MockKeyReader()
        let timer = CountdownTimer(isInteractive: true, keyReader: mockReader, onTick: { _ in },
                                   sleepDuration: .zero)
        let result = await timer.run(seconds: 2)
        #expect(result == .completed)
    }

    // Default countdown is 3
    @Test("Default countdown constant is 3")
    func stop_defaultCountdownIsThreeSeconds() {
        #expect(CountdownTimer.defaultCountdown == 3)
    }
}
