import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Helpers

private func makeTask(
    id: String = "task-1",
    prompt: String = "Implement feature X",
    targetNode: String? = nil,
    motoContext: MotoDispatchContext? = nil,
    priority: DispatchPriority = .normal,
    timeoutSeconds: Int = 300,
    companySlug: String = "maya"
) -> DispatchTask {
    DispatchTask(
        id: id,
        prompt: prompt,
        targetNode: targetNode,
        motoContext: motoContext,
        priority: priority,
        timeoutSeconds: timeoutSeconds,
        companySlug: companySlug
    )
}

private func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

// MARK: - NATSDispatcher Tests

@Suite("NATSDispatcher")
struct NATSDispatcherTests {

    // Scenario 1: Dispatcher publishes task to correct subject
    @Test("Dispatch publishes task as JSON to NATS")
    func dispatchPublishesTask() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let dispatcher = NATSDispatcher(nats: nats)

        let task = makeTask()
        try await dispatcher.dispatch(task: task)

        let published = await nats.publishedMessages
        #expect(published.count == 1)

        // Verify the payload decodes back to a valid DispatchTask
        let decoded = try makeDecoder().decode(DispatchTask.self, from: published[0].data)
        #expect(decoded.id == "task-1")
        #expect(decoded.prompt == "Implement feature X")
        #expect(decoded.companySlug == "maya")
    }

    // Scenario 2: Dispatcher with target node uses shikki.dispatch.{nodeId}
    @Test("Targeted dispatch uses node-specific subject")
    func targetedDispatch() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let dispatcher = NATSDispatcher(nats: nats)

        let task = makeTask(targetNode: "node-alpha")
        try await dispatcher.dispatch(task: task)

        let published = await nats.publishedMessages
        #expect(published.count == 1)
        #expect(published[0].subject == "shikki.dispatch.node-alpha")
    }

    // Scenario 3: Dispatcher without target uses shikki.dispatch.available
    @Test("Untargeted dispatch uses available subject")
    func untargetedDispatch() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let dispatcher = NATSDispatcher(nats: nats)

        let task = makeTask(targetNode: nil)
        try await dispatcher.dispatch(task: task)

        let published = await nats.publishedMessages
        #expect(published.count == 1)
        #expect(published[0].subject == "shikki.dispatch.available")
    }

    // Scenario 4: Worker receives task and publishes result
    @Test("Worker executes task and publishes result")
    func workerExecutesAndPublishes() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let executor = MockTaskExecutor()
        await executor.setOutput("feature implemented")
        let worker = NATSWorker(nats: nats, nodeId: "worker-1", executor: executor)

        await worker.start()

        // Give the subscriptions time to register
        try await Task.sleep(for: .milliseconds(50))

        // Simulate the orchestrator publishing a task to the available subject
        let task = makeTask(id: "task-42")
        let taskData = try makeEncoder().encode(task)
        await nats.injectMessage(NATSMessage(
            subject: NATSDispatchSubjects.available,
            data: taskData
        ))

        // Allow execution to complete
        try await Task.sleep(for: .milliseconds(100))

        // Verify the worker published a result
        let published = await nats.publishedMessages
        let resultMessages = published.filter { $0.subject == NATSDispatchSubjects.result(taskId: "task-42") }
        #expect(resultMessages.count == 1)

        let result = try makeDecoder().decode(NATSDispatchResult.self, from: resultMessages[0].data)
        #expect(result.taskId == "task-42")
        #expect(result.nodeId == "worker-1")
        #expect(result.status == .completed)
        #expect(result.output == "feature implemented")

        await worker.stop()
    }

    // Scenario 5: Worker streams progress events during execution
    @Test("Worker publishes progress events")
    func workerStreamsProgress() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let executor = MockTaskExecutor()
        await executor.setOutput("done")
        await executor.setProgressSteps([
            (1, "Parsing spec"),
            (2, "Generating code"),
            (3, "Running tests")
        ])
        let worker = NATSWorker(nats: nats, nodeId: "worker-1", executor: executor)

        await worker.start()
        try await Task.sleep(for: .milliseconds(50))

        let task = makeTask(id: "task-progress")
        let taskData = try makeEncoder().encode(task)
        await nats.injectMessage(NATSMessage(
            subject: NATSDispatchSubjects.available,
            data: taskData
        ))

        try await Task.sleep(for: .milliseconds(100))

        let published = await nats.publishedMessages
        let progressMessages = published.filter {
            $0.subject == NATSDispatchSubjects.progress(taskId: "task-progress")
        }
        #expect(progressMessages.count == 3)

        let firstProgress = try makeDecoder().decode(DispatchProgress.self, from: progressMessages[0].data)
        #expect(firstProgress.step == 1)
        #expect(firstProgress.message == "Parsing spec")
        #expect(firstProgress.nodeId == "worker-1")

        await worker.stop()
    }

    // Scenario 6: Dispatcher collects result after worker completes
    @Test("Dispatcher collects result via subscription")
    func dispatcherCollectsResult() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let dispatcher = NATSDispatcher(nats: nats)

        let taskId = "task-collect"

        // Start collecting result in a concurrent task
        let resultTask = Task {
            await dispatcher.collectResult(for: taskId, timeout: .seconds(2))
        }

        // Give subscription time to register
        try await Task.sleep(for: .milliseconds(50))

        // Simulate worker publishing a result
        let result = NATSDispatchResult(
            taskId: taskId,
            nodeId: "worker-2",
            status: .completed,
            output: "all tests pass",
            durationSeconds: 1.5
        )
        let resultData = try makeEncoder().encode(result)
        await nats.injectMessage(NATSMessage(
            subject: NATSDispatchSubjects.result(taskId: taskId),
            data: resultData
        ))

        let collected = await resultTask.value
        #expect(collected.taskId == taskId)
        #expect(collected.nodeId == "worker-2")
        #expect(collected.status == .completed)
        #expect(collected.output == "all tests pass")

        // Verify it's stored in dispatchedTasks
        let stored = await dispatcher.result(for: taskId)
        #expect(stored?.status == .completed)
    }

    // Scenario 7: Task with Moto context includes code slice in payload
    @Test("Task with Moto context serializes correctly")
    func taskWithMotoContext() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let dispatcher = NATSDispatcher(nats: nats)

        let context = MotoDispatchContext(
            projectId: "shikki",
            protocols: ["NATSClientProtocol", "TaskExecutor"],
            types: ["NATSDispatcher", "NATSWorker"],
            dependencies: ["NATSDispatcher": ["NATSClientProtocol"]],
            focusFiles: ["Sources/ShikkiKit/NATS/NATSDispatcher.swift"]
        )

        let task = makeTask(
            id: "task-moto",
            motoContext: context
        )
        try await dispatcher.dispatch(task: task)

        let published = await nats.publishedMessages
        #expect(published.count == 1)

        let decoded = try makeDecoder().decode(DispatchTask.self, from: published[0].data)
        #expect(decoded.motoContext != nil)
        #expect(decoded.motoContext?.projectId == "shikki")
        #expect(decoded.motoContext?.protocols == ["NATSClientProtocol", "TaskExecutor"])
        #expect(decoded.motoContext?.types == ["NATSDispatcher", "NATSWorker"])
        #expect(decoded.motoContext?.dependencies["NATSDispatcher"] == ["NATSClientProtocol"])
        #expect(decoded.motoContext?.focusFiles.count == 1)
    }

    // Scenario 8: Task timeout produces timeout result
    @Test("Collect result times out when no result arrives")
    func taskTimeout() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let dispatcher = NATSDispatcher(nats: nats)

        // Very short timeout — no result will be published
        let result = await dispatcher.collectResult(for: "task-timeout", timeout: .milliseconds(100))

        #expect(result.taskId == "task-timeout")
        #expect(result.status == .timeout)
    }

    // Scenario 9: Multiple tasks dispatched to different nodes
    @Test("Multiple tasks dispatched to different nodes")
    func multipleTasksToNodes() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let dispatcher = NATSDispatcher(nats: nats)

        let task1 = makeTask(id: "task-a", targetNode: "node-1")
        let task2 = makeTask(id: "task-b", targetNode: "node-2")
        let task3 = makeTask(id: "task-c", targetNode: nil)

        try await dispatcher.dispatch(task: task1)
        try await dispatcher.dispatch(task: task2)
        try await dispatcher.dispatch(task: task3)

        let published = await nats.publishedMessages
        #expect(published.count == 3)
        #expect(published[0].subject == "shikki.dispatch.node-1")
        #expect(published[1].subject == "shikki.dispatch.node-2")
        #expect(published[2].subject == "shikki.dispatch.available")

        let count = await dispatcher.dispatchCount
        #expect(count == 3)
    }

    // Scenario 10: Worker ignores tasks for other nodes
    @Test("Worker ignores tasks targeted at other nodes")
    func workerIgnoresOtherNodeTasks() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let executor = MockTaskExecutor()
        await executor.setOutput("executed")
        let worker = NATSWorker(nats: nats, nodeId: "worker-mine", executor: executor)

        await worker.start()
        try await Task.sleep(for: .milliseconds(50))

        // Send a task targeted at a DIFFERENT node via available subject
        // (simulates wildcard overlap scenario)
        let otherTask = makeTask(id: "task-other", targetNode: "worker-theirs")
        let otherData = try makeEncoder().encode(otherTask)
        await nats.injectMessage(NATSMessage(
            subject: NATSDispatchSubjects.available,
            data: otherData
        ))

        // Send a task with no target (should be picked up)
        let myTask = makeTask(id: "task-mine", targetNode: nil)
        let myData = try makeEncoder().encode(myTask)
        await nats.injectMessage(NATSMessage(
            subject: NATSDispatchSubjects.available,
            data: myData
        ))

        try await Task.sleep(for: .milliseconds(100))

        // Only the untargeted task should have been executed
        let executed = await executor.executedTasks
        #expect(executed.count == 1)
        #expect(executed[0].id == "task-mine")

        // Only one result should have been published
        let published = await nats.publishedMessages
        let resultMessages = published.filter { $0.subject.hasPrefix("shikki.dispatch.result.") }
        #expect(resultMessages.count == 1)
        #expect(resultMessages[0].subject == NATSDispatchSubjects.result(taskId: "task-mine"))

        await worker.stop()
    }
}

// MARK: - DispatchTask Model Tests

@Suite("DispatchTask Models")
struct DispatchTaskModelTests {

    @Test("DispatchTask round-trips through JSON")
    func taskRoundTrip() throws {
        let encoder = makeEncoder()
        let decoder = makeDecoder()

        let task = makeTask(
            id: "rt-1",
            prompt: "fix bug",
            targetNode: "node-x",
            priority: .high,
            timeoutSeconds: 120,
            companySlug: "shiki"
        )

        let data = try encoder.encode(task)
        let decoded = try decoder.decode(DispatchTask.self, from: data)

        #expect(decoded.id == "rt-1")
        #expect(decoded.prompt == "fix bug")
        #expect(decoded.targetNode == "node-x")
        #expect(decoded.priority == .high)
        #expect(decoded.timeoutSeconds == 120)
        #expect(decoded.companySlug == "shiki")
    }

    @Test("NATSDispatchResult round-trips through JSON")
    func resultRoundTrip() throws {
        let encoder = makeEncoder()
        let decoder = makeDecoder()

        let result = NATSDispatchResult(
            taskId: "t-1",
            nodeId: "n-1",
            status: .completed,
            output: "done",
            durationSeconds: 2.5
        )

        let data = try encoder.encode(result)
        let decoded = try decoder.decode(NATSDispatchResult.self, from: data)

        #expect(decoded.taskId == "t-1")
        #expect(decoded.nodeId == "n-1")
        #expect(decoded.status == .completed)
        #expect(decoded.output == "done")
        #expect(decoded.durationSeconds == 2.5)
    }

    @Test("DispatchProgress round-trips through JSON")
    func progressRoundTrip() throws {
        let encoder = makeEncoder()
        let decoder = makeDecoder()

        let progress = DispatchProgress(
            taskId: "t-1",
            nodeId: "n-1",
            step: 3,
            message: "compiling"
        )

        let data = try encoder.encode(progress)
        let decoded = try decoder.decode(DispatchProgress.self, from: data)

        #expect(decoded.taskId == "t-1")
        #expect(decoded.nodeId == "n-1")
        #expect(decoded.step == 3)
        #expect(decoded.message == "compiling")
    }

    @Test("NATSDispatchSubjects generates correct subjects")
    func subjectNaming() {
        #expect(NATSDispatchSubjects.targeted(nodeId: "abc") == "shikki.dispatch.abc")
        #expect(NATSDispatchSubjects.available == "shikki.dispatch.available")
        #expect(NATSDispatchSubjects.progress(taskId: "t1") == "shikki.dispatch.progress.t1")
        #expect(NATSDispatchSubjects.result(taskId: "t1") == "shikki.dispatch.result.t1")
        #expect(NATSDispatchSubjects.allProgress == "shikki.dispatch.progress.>")
        #expect(NATSDispatchSubjects.allResults == "shikki.dispatch.result.>")
    }

    @Test("DispatchPriority ordering is correct")
    func priorityOrdering() {
        #expect(DispatchPriority.low < .normal)
        #expect(DispatchPriority.normal < .high)
        #expect(DispatchPriority.high < .critical)
    }

    @Test("Dispatcher throws when not connected")
    func dispatcherNotConnected() async {
        let nats = MockNATSClient()
        let dispatcher = NATSDispatcher(nats: nats)

        let task = makeTask()
        do {
            try await dispatcher.dispatch(task: task)
            Issue.record("Expected NATSDispatcherError.notConnected")
        } catch {
            #expect(error is NATSDispatcherError)
        }
    }

    @Test("Worker failed execution produces failed result")
    func workerFailedExecution() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let executor = MockTaskExecutor()
        await executor.setThrows(true)
        let worker = NATSWorker(nats: nats, nodeId: "worker-fail", executor: executor)

        await worker.start()
        try await Task.sleep(for: .milliseconds(50))

        let task = makeTask(id: "task-fail")
        let taskData = try makeEncoder().encode(task)
        await nats.injectMessage(NATSMessage(
            subject: NATSDispatchSubjects.available,
            data: taskData
        ))

        try await Task.sleep(for: .milliseconds(100))

        let published = await nats.publishedMessages
        let resultMessages = published.filter {
            $0.subject == NATSDispatchSubjects.result(taskId: "task-fail")
        }
        #expect(resultMessages.count == 1)

        let result = try makeDecoder().decode(NATSDispatchResult.self, from: resultMessages[0].data)
        #expect(result.status == .failed)
        #expect(result.nodeId == "worker-fail")

        await worker.stop()
    }
}
