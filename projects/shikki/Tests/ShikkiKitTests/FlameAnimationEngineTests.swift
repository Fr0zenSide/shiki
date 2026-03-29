import Testing
@testable import ShikkiKit

// MARK: - FlameAnimationEngineTests

@Suite("FlameAnimationEngine — animation state and event processing")
struct FlameAnimationEngineTests {

    // MARK: Initial State

    @Test("engine starts in calm emotion")
    func initialEmotionIsCalm() async {
        let engine = FlameAnimationEngine()
        let state = await engine.currentState
        #expect(state.emotion == .calm)
    }

    @Test("engine starts at frame 0")
    func initialFrameIsZero() async {
        let engine = FlameAnimationEngine()
        let state = await engine.currentState
        #expect(state.frameIndex == 0)
    }

    @Test("engine defaults to medium size")
    func initialSizeIsMedium() async {
        let engine = FlameAnimationEngine()
        let state = await engine.currentState
        #expect(state.size == .medium)
    }

    @Test("engine respects initial size parameter")
    func customInitialSize() async {
        let engine = FlameAnimationEngine(size: .large)
        let state = await engine.currentState
        #expect(state.size == .large)
    }

    // MARK: Size Control

    @Test("setSize updates the flame size")
    func setSizeUpdates() async {
        let engine = FlameAnimationEngine()
        await engine.setSize(.mini)
        let state = await engine.currentState
        #expect(state.size == .mini)
    }

    // MARK: Emotion Control

    @Test("setEmotion updates flame emotion")
    func setEmotionUpdates() async {
        let engine = FlameAnimationEngine()
        await engine.setEmotion(.excited)
        let state = await engine.currentState
        #expect(state.emotion == .excited)
    }

    @Test("setEmotion resets frame index to 0")
    func setEmotionResetsFrame() async {
        let engine = FlameAnimationEngine()
        // Advance a few ticks
        _ = await engine.tick()
        _ = await engine.tick()
        await engine.setEmotion(.alarmed)
        let state = await engine.currentState
        #expect(state.frameIndex == 0)
    }

    // MARK: Tick Behavior

    @Test("tick returns rendered lines")
    func tickReturnsLines() async {
        let engine = FlameAnimationEngine()
        let lines = await engine.tick()
        #expect(!lines.isEmpty)
    }

    @Test("tick increments tick count")
    func tickIncrementsCount() async {
        let engine = FlameAnimationEngine()
        _ = await engine.tick()
        _ = await engine.tick()
        let state = await engine.currentState
        #expect(state.tickCount == 2)
    }

    @Test("tick returns medium-sized output by default")
    func tickReturnsMediumSize() async {
        let engine = FlameAnimationEngine()
        let lines = await engine.tick()
        // Medium frames are 8 lines
        #expect(lines.count == 8)
    }

    @Test("tick with mini size returns single line")
    func tickWithMiniSize() async {
        let engine = FlameAnimationEngine(size: .mini)
        let lines = await engine.tick()
        #expect(lines.count == 1)
    }

    // MARK: Event Processing

    @Test("processEvent updates emotion based on event type")
    func processEventUpdatesEmotion() async {
        let engine = FlameAnimationEngine()
        let event = ShikkiEvent(
            source: .orchestrator,
            type: .shipCompleted,
            scope: .global
        )
        await engine.processEvent(event)
        let state = await engine.currentState
        #expect(state.emotion == .celebrating)
    }

    @Test("processEvent upgrades but does not downgrade emotion")
    func processEventOnlyUpgrades() async {
        let engine = FlameAnimationEngine()

        // Set to alarmed
        let alarm = ShikkiEvent(source: .system, type: .budgetExhausted, scope: .global)
        await engine.processEvent(alarm)
        #expect(await engine.currentState.emotion == .alarmed)

        // Try to downgrade with a calm event — should not change
        let calm = ShikkiEvent(source: .system, type: .heartbeat, scope: .global)
        await engine.processEvent(calm)
        #expect(await engine.currentState.emotion == .alarmed)
    }

    @Test("processEvent upgrades from focused to excited")
    func processEventUpgradesToExcited() async {
        let engine = FlameAnimationEngine()

        let focus = ShikkiEvent(source: .system, type: .codeChange, scope: .global)
        await engine.processEvent(focus)
        #expect(await engine.currentState.emotion == .focused)

        let excite = ShikkiEvent(source: .system, type: .decisionAnswered, scope: .global)
        await engine.processEvent(excite)
        #expect(await engine.currentState.emotion == .excited)
    }

    // MARK: Emotion Decay

    @Test("focused emotion decays to calm after enough ticks")
    func focusedDecays() async {
        let engine = FlameAnimationEngine()
        await engine.setEmotion(.focused)

        // Focused decays after 20 ticks
        for _ in 0..<21 {
            _ = await engine.tick()
        }
        let state = await engine.currentState
        #expect(state.emotion == .calm)
    }

    @Test("calm emotion never decays")
    func calmNeverDecays() async {
        let engine = FlameAnimationEngine()
        for _ in 0..<100 {
            _ = await engine.tick()
        }
        let state = await engine.currentState
        #expect(state.emotion == .calm)
    }

    @Test("event resets decay counter")
    func eventResetsDecay() async {
        let engine = FlameAnimationEngine()
        await engine.setEmotion(.focused)

        // Tick 18 times (2 short of decay)
        for _ in 0..<18 {
            _ = await engine.tick()
        }
        #expect(await engine.currentState.emotion == .focused)

        // Process a focused event to reset the decay counter
        let event = ShikkiEvent(source: .system, type: .codeChange, scope: .global)
        await engine.processEvent(event)

        // Tick 18 more times — should still be focused since counter was reset
        for _ in 0..<18 {
            _ = await engine.tick()
        }
        #expect(await engine.currentState.emotion == .focused)
    }

    // MARK: EventBus Integration

    @Test("engine can be created with EventBus")
    func creationWithBus() async {
        let bus = InProcessEventBus()
        let engine = FlameAnimationEngine(bus: bus, size: .medium)
        let state = await engine.currentState
        #expect(state.emotion == .calm)
    }

    // MARK: Animation Config

    @Test("calm has slowest frame interval")
    func calmSlowestInterval() {
        let config = FlameAnimationConfig.config(for: .calm)
        #expect(config.frameInterval == 1.0)
    }

    @Test("alarmed has fastest frame interval")
    func alarmedFastestInterval() {
        let config = FlameAnimationConfig.config(for: .alarmed)
        #expect(config.frameInterval == 0.15)
    }

    @Test("calm never decays (max decay ticks)")
    func calmMaxDecay() {
        let config = FlameAnimationConfig.config(for: .calm)
        #expect(config.decayTicks == .max)
    }

    @Test("excited has shorter decay than focused")
    func excitedShorterDecayThanFocused() {
        let excitedConfig = FlameAnimationConfig.config(for: .excited)
        let focusedConfig = FlameAnimationConfig.config(for: .focused)
        #expect(excitedConfig.decayTicks < focusedConfig.decayTicks)
    }
}

// MARK: - FlameAnimationState Tests

@Suite("FlameAnimationState — state model")
struct FlameAnimationStateTests {

    @Test("default state is calm, frame 0, medium, tick 0")
    func defaultState() {
        let state = FlameAnimationState()
        #expect(state.emotion == .calm)
        #expect(state.frameIndex == 0)
        #expect(state.size == .medium)
        #expect(state.tickCount == 0)
    }

    @Test("state supports custom initialization")
    func customState() {
        let state = FlameAnimationState(
            emotion: .excited,
            frameIndex: 2,
            size: .large,
            tickCount: 42
        )
        #expect(state.emotion == .excited)
        #expect(state.frameIndex == 2)
        #expect(state.size == .large)
        #expect(state.tickCount == 42)
    }

    @Test("state is Equatable")
    func stateEquatable() {
        let a = FlameAnimationState(emotion: .calm, frameIndex: 0, size: .medium, tickCount: 0)
        let b = FlameAnimationState(emotion: .calm, frameIndex: 0, size: .medium, tickCount: 0)
        #expect(a == b)
    }
}
