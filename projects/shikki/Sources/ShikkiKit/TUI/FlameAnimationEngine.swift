import Foundation

// MARK: - FlameAnimationState

/// Snapshot of the flame's current animation state.
/// Exposed for testing and dashboard integration.
public struct FlameAnimationState: Sendable, Equatable {
    public var emotion: FlameEmotion
    public var frameIndex: Int
    public var size: FlameSize
    public var tickCount: Int

    public init(
        emotion: FlameEmotion = .calm,
        frameIndex: Int = 0,
        size: FlameSize = .medium,
        tickCount: Int = 0
    ) {
        self.emotion = emotion
        self.frameIndex = frameIndex
        self.size = size
        self.tickCount = tickCount
    }
}

// MARK: - FlameAnimationConfig

/// Configuration for animation timing per emotion.
public struct FlameAnimationConfig: Sendable {
    /// Interval between frames in seconds.
    public let frameInterval: TimeInterval
    /// How many ticks an emotion persists before decaying back to calm.
    public let decayTicks: Int

    public init(frameInterval: TimeInterval, decayTicks: Int) {
        self.frameInterval = frameInterval
        self.decayTicks = decayTicks
    }

    /// Default timing for each emotion.
    public static func config(for emotion: FlameEmotion) -> FlameAnimationConfig {
        switch emotion {
        case .calm:
            return FlameAnimationConfig(frameInterval: 1.0, decayTicks: .max)
        case .focused:
            return FlameAnimationConfig(frameInterval: 0.5, decayTicks: 20)
        case .excited:
            return FlameAnimationConfig(frameInterval: 0.3, decayTicks: 10)
        case .alarmed:
            return FlameAnimationConfig(frameInterval: 0.15, decayTicks: 16)
        case .celebrating:
            return FlameAnimationConfig(frameInterval: 0.2, decayTicks: 15)
        }
    }
}

// MARK: - FlameAnimationEngine

/// Drives the flame animation loop, reacting to events from the EventBus.
///
/// The engine maintains a current emotion and frame counter. When events arrive,
/// the emotion resolver determines if the flame should change state. Emotions
/// decay back to `.calm` after a configurable number of ticks without new stimulus.
///
/// Usage:
/// ```swift
/// let engine = FlameAnimationEngine(bus: eventBus, size: .medium)
/// for await frame in engine.frames() {
///     // frame is a rendered [String] array ready for display
/// }
/// ```
public actor FlameAnimationEngine {
    private var state: FlameAnimationState
    private let bus: InProcessEventBus?
    private var ticksSinceLastEvent: Int = 0

    /// Event types that the flame reacts to (everything except noise-level heartbeats
    /// which would cause constant flickering).
    private static let reactiveTypes: Set<EventType> = [
        .sessionStart, .sessionEnd, .sessionTransition,
        .codeChange, .testRun, .buildResult,
        .decisionPending, .decisionAnswered, .decisionUnblocked,
        .companyDispatched, .companyStale, .companyRelaunched,
        .budgetExhausted,
        .prVerdictSet, .prFixSpawned, .prFixCompleted,
        .shipStarted, .shipGateStarted, .shipGatePassed,
        .shipGateFailed, .shipCompleted, .shipAborted,
        .codeGenStarted, .codeGenPipelineCompleted, .codeGenPipelineFailed,
        .notificationActioned,
    ]

    // MARK: - Init

    /// Create an engine optionally connected to an EventBus.
    /// Pass `nil` for bus in testing scenarios where you drive state manually.
    public init(bus: InProcessEventBus? = nil, size: FlameSize = .medium) {
        self.bus = bus
        self.state = FlameAnimationState(size: size)
    }

    // MARK: - Public API

    /// Current animation state (for inspection/testing).
    public var currentState: FlameAnimationState { state }

    /// Set the flame size.
    public func setSize(_ size: FlameSize) {
        state.size = size
    }

    /// Manually set emotion (useful for testing or direct control).
    public func setEmotion(_ emotion: FlameEmotion) {
        state.emotion = emotion
        state.frameIndex = 0
        ticksSinceLastEvent = 0
    }

    /// Advance one animation tick. Returns the rendered frame lines.
    /// Call this at the configured frame interval.
    public func tick() -> [String] {
        let config = FlameAnimationConfig.config(for: state.emotion)

        // Decay to calm if no recent events
        if state.emotion != .calm {
            ticksSinceLastEvent += 1
            if ticksSinceLastEvent >= config.decayTicks {
                state.emotion = .calm
                state.frameIndex = 0
                ticksSinceLastEvent = 0
            }
        }

        let frameCount = FlameRenderer.frameCount(size: state.size, emotion: state.emotion)
        state.frameIndex = state.tickCount % max(frameCount, 1)
        state.tickCount += 1

        return FlameRenderer.render(
            size: state.size,
            emotion: state.emotion,
            frame: state.frameIndex
        )
    }

    /// Process a single event and update the flame emotion accordingly.
    public func processEvent(_ event: ShikkiEvent) {
        let newEmotion = FlameEmotionResolver.resolve(event.type)
        let currentPriority = FlameEmotionResolver.priority(state.emotion)
        let newPriority = FlameEmotionResolver.priority(newEmotion)

        // Only upgrade emotion, never downgrade from events (decay handles that)
        if newPriority >= currentPriority {
            state.emotion = newEmotion
            state.frameIndex = 0
            ticksSinceLastEvent = 0
        }
    }

    /// Start the animation loop, yielding rendered frames as an AsyncStream.
    /// Subscribes to the EventBus for emotion updates.
    /// Cancel the consuming task to stop the loop.
    public func frames() -> AsyncStream<[String]> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                // Start EventBus subscription if available
                let eventTask: Task<Void, Never>?
                if let bus = await self.bus {
                    let filter = EventFilter(types: Self.reactiveTypes)
                    let stream = await bus.subscribe(filter: filter)
                    eventTask = Task {
                        for await event in stream {
                            await self.processEvent(event)
                        }
                    }
                } else {
                    eventTask = nil
                }

                // Animation loop
                while !Task.isCancelled {
                    let frame = await self.tick()
                    continuation.yield(frame)

                    let config = FlameAnimationConfig.config(
                        for: await self.currentState.emotion
                    )
                    try? await Task.sleep(for: .milliseconds(
                        Int(config.frameInterval * 1000)
                    ))
                }

                eventTask?.cancel()
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
