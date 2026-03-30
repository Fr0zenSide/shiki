import Testing

extension Tag {
    /// Tests that spawn the compiled binary and assert on exit codes/output.
    /// These require a prior `swift build` and may hang if the binary reads stdin.
    /// Skip with: SKIP_E2E=1 swift test
    @Tag static var e2e: Self
}
