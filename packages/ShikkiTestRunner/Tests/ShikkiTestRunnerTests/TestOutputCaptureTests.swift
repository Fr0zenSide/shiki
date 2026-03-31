// TestOutputCaptureTests.swift — Tests for output capture and buffering
// Part of ShikkiTestRunnerTests

import Foundation
import Testing
@testable import ShikkiTestRunner

@Suite("TestOutputCapture")
struct TestOutputCaptureTests {

    @Test("captures stdout lines into buffer")
    func captureStdout() async {
        let buffer = OutputBuffer()
        let capture = TestOutputCapture()

        let output = ProcessOutput(
            stdout: "line1\nline2\nline3",
            stderr: "",
            exitCode: 0
        )

        await capture.capture(output: output, into: buffer)

        let content = await buffer.stdoutContent()
        #expect(content.contains("line1"))
        #expect(content.contains("line2"))
        #expect(content.contains("line3"))
    }

    @Test("captures stderr lines separately from stdout")
    func separateStdoutStderr() async {
        let buffer = OutputBuffer()
        let capture = TestOutputCapture()

        let output = ProcessOutput(
            stdout: "out1\nout2",
            stderr: "err1\nerr2",
            exitCode: 0
        )

        await capture.capture(output: output, into: buffer)

        let stdoutContent = await buffer.stdoutContent()
        let stderrContent = await buffer.stderrContent()
        #expect(stdoutContent.contains("out1"))
        #expect(!stdoutContent.contains("err1"))
        #expect(stderrContent.contains("err1"))
        #expect(!stderrContent.contains("out1"))
    }

    @Test("captures logger messages with logger source tag")
    func captureLoggerMessages() async {
        let buffer = OutputBuffer()
        let capture = TestOutputCapture()

        await capture.captureLogMessage("[info] kernel booting...", into: buffer)
        await capture.captureLogMessage("[debug] service registered", into: buffer)

        let logContent = await buffer.loggerContent()
        #expect(logContent.contains("kernel booting"))
        #expect(logContent.contains("service registered"))

        // Logger content should not appear in stdout
        let stdoutContent = await buffer.stdoutContent()
        #expect(stdoutContent.isEmpty)
    }

    @Test("rawOutput combines all sources")
    func rawOutputCombinesAll() async {
        let buffer = OutputBuffer()
        let capture = TestOutputCapture()

        let output = ProcessOutput(
            stdout: "stdout-line",
            stderr: "stderr-line",
            exitCode: 0
        )

        await capture.capture(output: output, into: buffer)
        await capture.captureLogMessage("logger-line", into: buffer)

        let raw = await buffer.rawOutput()
        #expect(raw.contains("stdout-line"))
        #expect(raw.contains("stderr-line"))
        #expect(raw.contains("logger-line"))
    }

    @Test("buffer clear removes all content")
    func bufferClear() async {
        let buffer = OutputBuffer()
        await buffer.append("test line", source: .stdout)

        let countBefore = await buffer.lineCount()
        #expect(countBefore == 1)

        await buffer.clear()

        let countAfter = await buffer.lineCount()
        #expect(countAfter == 0)
    }
}
