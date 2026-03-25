/// Protocol for event persistence, enabling test injection.
/// The concrete `EventPersister` conforms to this.
public protocol EventPersisting: Sendable {
    func persist(_ event: LifecycleEventPayload) async
}

extension EventPersister: EventPersisting {}
