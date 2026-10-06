// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum T3CodeActivityTests {
    static func run(_ suite: TestSuite) {
        mapping(suite)
        transitions(suite)
        compactPresentation(suite)
        endpointValidation(suite)
        localization(suite)
    }

    private static let environment = T3EnvironmentIdentity(id: "env-local", label: "Local Mac", machine: "MacBook")

    private static func snapshot(status: String, activity: String? = nil, request: String? = nil,
                                 activeRun: String? = "run-1", completedAt: String? = nil,
                                 startedAt: String? = "2026-10-06T12:00:00Z", updatedAt: String = "2026-10-06T12:01:00Z",
                                 activityStartedAt: String? = nil,
                                 latestRunWorkStartedAt: String? = nil,
                                 latestUserAuthoredAt: String? = "2026-10-06T12:00:00Z",
                                 latestUserMessageAt: String? = nil,
                                 latestRunID: String = "run-1", backgroundKinds: [String] = [],
                                 duplicateProject: Bool = false) -> [T3ThreadActivity] {
        let runStatus = activity.map { "\"\($0)\"" } ?? "null"
        let runStart = startedAt.map { "\"\($0)\"" } ?? "null"
        let activityStart = activityStartedAt.map { "\"\($0)\"" } ?? "null"
        let latestWorkStart = latestRunWorkStartedAt.map { "\"\($0)\"" } ?? "null"
        let latestUserAuthored = latestUserAuthoredAt.map { "\"\($0)\"" } ?? "null"
        let latestUserMessage = latestUserMessageAt.map { "\"\($0)\"" } ?? "null"
        let completed = completedAt.map { "\"\($0)\"" } ?? "null"
        let active = activeRun.map { "\"\($0)\"" } ?? "null"
        let pending = request.map { "{\"kind\":\"\($0)\"}" } ?? "null"
        let background = "[" + backgroundKinds.enumerated().map { index, kind in
            "{\"taskId\":\"task-\(index)\",\"kind\":\"\(kind)\"}"
        }.joined(separator: ",") + "]"
        let projects = duplicateProject
            ? "[{\"id\":\"project-1\",\"title\":\"MowgliNext\"},{\"id\":\"project-1\",\"title\":\"Duplicate\"}]"
            : "[{\"id\":\"project-1\",\"title\":\"MowgliNext\"}]"
        let json = """
        {"threads":[{"id":"thread-1","projectId":"project-1","title":"Fix USB recovery",
          "providerInstanceId":"codex","modelSelection":{"instanceId":"codex","model":"gpt-5.4"},
          "status":"\(status)","activityRunStatus":\(runStatus),"activityRunStartedAt":\(activityStart),
          "latestRunWorkStartedAt":\(latestWorkStart),
          "latestUserAuthoredMessageAt":\(latestUserAuthored),
          "latestUserMessageAt":\(latestUserMessage),
          "latestRunStartedAt":\(runStart),"latestRunCompletedAt":\(completed),
          "latestRunId":"\(latestRunID)","activeRunId":\(active),"pendingRuntimeRequest":\(pending),
          "pendingBackgroundTasks":\(background),"updatedAt":"\(updatedAt)"}],
         "archivedThreads":[],"projects":\(projects)}
        """
        let decoded = try? JSONDecoder().decode(T3ShellSnapshot.self, from: Data(json.utf8))
        return decoded?.activities(environment: environment) ?? []
    }

    private static func mapping(_ suite: TestSuite) {
        suite.expect(snapshot(status: "running", activity: "running").first?.state == .working,
                     "T3 running threads map to working")
        suite.expect(snapshot(status: "waiting", request: "permission").first?.state == .waitingForApproval,
                     "permission requests map to approval priority")
        for kind in ["command", "file-read", "file-change", "mcp-elicitation", "dynamic_tool_call"] {
            suite.expect(snapshot(status: "waiting", request: kind).first?.state == .waitingForApproval,
                         "T3 \(kind) requests map to approval priority")
        }
        suite.expect(snapshot(status: "waiting", request: "user_input").first?.state == .waitingForInput,
                     "user input requests map to input priority")
        suite.expect(snapshot(status: "waiting").first?.state == .waiting,
                     "a waiting run without a request remains waiting")
        suite.expect(snapshot(status: "completed", activeRun: nil,
                              completedAt: "2026-10-06T12:01:00Z").first?.state == .completed,
                     "completed runs map to completed")
        suite.expect(snapshot(status: "failed", activeRun: nil).first?.state == .failed,
                     "failed runs map to failed")
        suite.expect(snapshot(status: "cancelled", activeRun: nil).first?.state == .stopped,
                     "cancelled runs map to stopped")
        for status in ["cancelled", "interrupted"] {
            suite.expect(snapshot(status: status, activeRun: nil, backgroundKinds: ["monitor"])
                            .first?.state == .waiting,
                         "T3 \(status) runs with pending monitors remain visible as waiting")
        }
        suite.expect(snapshot(status: "rolled_back", activeRun: nil, backgroundKinds: ["monitor"])
                        .first?.state == .stopped,
                     "rolled-back runs stay stopped even if stale background work is present")
        suite.expect(snapshot(status: "idle", activeRun: nil, completedAt: nil).first?.state == .idle,
                     "idle threads do not appear as active")
        let thread = snapshot(status: "running", activity: "running").first
        suite.expect(thread?.project == "MowgliNext" && thread?.title == "Fix USB recovery"
                        && thread?.environment == "Local Mac" && thread?.machine == "MacBook"
                        && thread?.provider == "codex" && thread?.model == "gpt-5.4",
                     "T3 shell metadata maps project, environment, provider, and model")
        suite.expect(thread?.location == "MowgliNext · Local Mac (MacBook)",
                     "T3 thread location keeps its environment label when machine metadata is present")
        suite.expect(thread?.latestRunWorkStartedAt == nil
                        && snapshot(status: "running", activity: "running",
                                    latestRunWorkStartedAt: "2026-10-06T11:59:00Z").first?.latestRunWorkStartedAt
                            == ISO8601DateFormatter().date(from: "2026-10-06T11:59:00Z"),
                     "the optional per-run work start maps when supplied and remains compatible with older shells")
        suite.expect(snapshot(status: "running", activity: "running", duplicateProject: true)
                        .first?.project == "MowgliNext",
                     "duplicate project ids are handled without crashing or changing the first title")
        suite.expect(snapshot(status: "running", activity: "running", startedAt: nil,
                              updatedAt: "not-a-date").isEmpty,
                     "malformed timestamps skip an unexpected thread without failing the shell")
        suite.expect(snapshot(status: "running", activity: "running", backgroundKinds: ["monitor"])
                        .first?.backgroundTaskCount == 1,
                     "pending background work is retained in the activity")
        suite.expect(snapshot(status: "completed", activeRun: nil, completedAt: "2026-10-06T12:01:00Z",
                              backgroundKinds: ["command"]).first?.state == .completed,
                     "a pending background command does not keep a completed thread active")
        suite.expect(snapshot(status: "running", activity: "running", backgroundKinds: ["subagent"])
                        .first?.state == .working,
                     "an active T3 run remains working even when background activity is present")
        suite.expect(snapshot(status: "failed", activeRun: nil, backgroundKinds: ["monitor"])
                        .first?.state == .failed,
                     "pending monitor work does not hide a failed T3 run")
        for kind in ["monitor", "subagent", "background_task", "future-kind"] {
            suite.expect(snapshot(status: "completed", activeRun: nil, completedAt: "2026-10-06T12:01:00Z",
                                  backgroundKinds: [kind]).first?.state == .waiting,
                         "T3 \(kind) background work keeps a settled thread visible without marking the root run working")
        }
    }

    private static func transitions(_ suite: TestSuite) {
        var reducer = T3ActivityReducer()
        let working = snapshot(status: "running", activity: "running")
        let finished = snapshot(status: "completed", activeRun: nil,
                                completedAt: "2026-10-06T12:02:00Z", updatedAt: "2026-10-06T12:32:00Z")
        suite.expect(reducer.apply(finished).isEmpty, "the initial snapshot suppresses historical completion notices")
        _ = reducer.apply(working)
        let completions = reducer.apply(finished)
        suite.expect(completions.count == 1 && completions.first?.activity.threadID == "thread-1"
                        && completions.first?.duration == 120,
                     "completion duration uses run completion time, not thread modification time")
        suite.expect(reducer.apply(finished).isEmpty, "repeated completion snapshots do not duplicate events")

        var backgroundTaskCompletionReducer = T3ActivityReducer()
        _ = backgroundTaskCompletionReducer.apply(working)
        let rootFinishedWithMonitor = snapshot(status: "completed", activeRun: nil,
                                               completedAt: "2026-10-06T12:02:00Z", backgroundKinds: ["monitor"])
        suite.expect(backgroundTaskCompletionReducer.apply(rootFinishedWithMonitor).isEmpty,
                     "T3 background work holds the completion until its roster clears")
        let monitorFinished = snapshot(status: "completed", activeRun: nil,
                                       completedAt: "2026-10-06T12:02:00Z")
        suite.expect(backgroundTaskCompletionReducer.apply(monitorFinished).count == 1
                        && backgroundTaskCompletionReducer.apply(monitorFinished).isEmpty,
                     "clearing T3 background work announces completion once")

        var resumedRun = T3ActivityReducer()
        let resumed = snapshot(status: "running", activity: "running",
                               startedAt: "2026-10-06T12:04:55Z", activityStartedAt: "2026-10-06T12:00:00Z")
        let resumedFinished = snapshot(status: "completed", activeRun: nil,
                                        completedAt: "2026-10-06T12:05:00Z", startedAt: "2026-10-06T12:04:55Z",
                                        updatedAt: "2026-10-06T12:05:00Z", activityStartedAt: nil,
                                        latestRunWorkStartedAt: "2026-10-06T12:00:00Z")
        _ = resumedRun.apply(resumed)
        let resumedCompletion = resumedRun.apply(resumedFinished).first
        suite.expect(resumedCompletion?.duration == 300,
                     "completion after a wake run keeps the original active work start")

        var backgroundWake = T3ActivityReducer()
        let rootWork = snapshot(status: "running", activity: "running",
                                activityStartedAt: "2026-10-06T12:00:00Z")
        let pendingMonitor = snapshot(status: "completed", activeRun: nil,
                                      completedAt: "2026-10-06T12:02:00Z",
                                      activityStartedAt: "2026-10-06T12:00:00Z", backgroundKinds: ["monitor"])
        let wakeRun = snapshot(status: "running", activity: "running", startedAt: "2026-10-06T12:04:55Z",
                               activityStartedAt: "2026-10-06T12:00:00Z", latestRunID: "run-2")
        let wakeFinished = snapshot(status: "completed", activeRun: nil,
                                    completedAt: "2026-10-06T12:05:00Z", startedAt: "2026-10-06T12:04:55Z",
                                    activityStartedAt: "2026-10-06T12:00:00Z",
                                    latestRunWorkStartedAt: "2026-10-06T12:00:00Z", latestRunID: "run-2")
        _ = backgroundWake.apply(rootWork)
        _ = backgroundWake.apply(pendingMonitor)
        _ = backgroundWake.apply(wakeRun)
        let backgroundCompletion = backgroundWake.apply(wakeFinished).first
        suite.expect(backgroundCompletion?.duration == 300,
                     "completion across a background wake with a new run id keeps the activity duration")

        var directWakeCompletion = T3ActivityReducer()
        _ = directWakeCompletion.apply(rootWork)
        _ = directWakeCompletion.apply(pendingMonitor)
        let completedWake = snapshot(status: "completed", activeRun: nil,
                                     completedAt: "2026-10-06T12:05:00Z", startedAt: "2026-10-06T12:04:55Z",
                                     activityStartedAt: nil, latestRunWorkStartedAt: "2026-10-06T12:00:00Z",
                                     latestRunID: "run-2")
        suite.expect(directWakeCompletion.apply(completedWake).first?.duration == 300,
                     "a wake that completes between polls keeps the original duration after activity start clears")

        var unrelatedRun = T3ActivityReducer()
        _ = unrelatedRun.apply(working)
        let shortNewRun = snapshot(status: "completed", activeRun: nil,
                                   completedAt: "2026-10-06T12:10:02Z", startedAt: "2026-10-06T12:10:00Z",
                                   latestUserAuthoredAt: "2026-10-06T12:10:00Z", latestRunID: "run-2")
        suite.expect(unrelatedRun.apply(shortNewRun).first?.duration == 2,
                     "a distinct new user run does not inherit the previous task duration")

        var newRunAfterMonitor = T3ActivityReducer()
        _ = newRunAfterMonitor.apply(rootWork)
        _ = newRunAfterMonitor.apply(pendingMonitor)
        let newRunStarted = snapshot(status: "running", activity: "running",
                                     startedAt: "2026-10-06T12:10:00Z",
                                     activityStartedAt: "2026-10-06T12:10:00Z",
                                     latestUserAuthoredAt: "2026-10-06T12:10:00Z", latestRunID: "run-2",
                                     backgroundKinds: ["monitor"])
        _ = newRunAfterMonitor.apply(newRunStarted)
        let newRunFinished = snapshot(status: "completed", activeRun: nil,
                                      completedAt: "2026-10-06T12:10:02Z",
                                      startedAt: "2026-10-06T12:10:00Z",
                                      latestUserAuthoredAt: "2026-10-06T12:10:00Z", latestRunID: "run-2")
        suite.expect(newRunAfterMonitor.apply(newRunFinished).first?.duration == 2,
                     "a new user run after a monitor honors T3's authoritative activity start")

        var newRunAfterWaiting = T3ActivityReducer()
        let waiting = snapshot(status: "waiting", activeRun: nil,
                               latestUserAuthoredAt: "2026-10-06T12:00:00Z")
        _ = newRunAfterWaiting.apply(working)
        _ = newRunAfterWaiting.apply(waiting)
        let finishedAfterWaiting = snapshot(status: "completed", activeRun: nil,
                                             completedAt: "2026-10-06T12:10:02Z",
                                             startedAt: "2026-10-06T12:10:00Z",
                                             latestUserAuthoredAt: "2026-10-06T12:10:00Z", latestRunID: "run-2")
        suite.expect(newRunAfterWaiting.apply(finishedAfterWaiting).first?.duration == 2,
                     "a user run after waiting starts a new completion duration")

        var queuedRun = T3ActivityReducer()
        let firstRun = snapshot(status: "running", activity: "running", startedAt: "2026-10-06T12:00:00Z",
                                activityStartedAt: "2026-10-06T12:00:00Z", latestUserAuthoredAt: "2026-10-06T12:00:00Z",
                                latestRunID: "run-1")
        let queuedSecondRun = snapshot(status: "waiting", activeRun: nil, startedAt: nil,
                                       activityStartedAt: "2026-10-06T12:00:00Z",
                                       latestUserAuthoredAt: nil, latestRunID: "run-2")
        let secondRunFinished = snapshot(status: "completed", activeRun: nil,
                                         completedAt: "2026-10-06T12:10:02Z",
                                         startedAt: "2026-10-06T12:10:00Z",
                                         latestUserAuthoredAt: "2026-10-06T12:10:00Z", latestRunID: "run-2")
        _ = queuedRun.apply(firstRun)
        _ = queuedRun.apply(queuedSecondRun)
        suite.expect(queuedSecondRun.first?.activityRunID == nil,
                     "a waiting activity does not claim ownership of the latest queued run")
        suite.expect(queuedRun.apply(secondRunFinished).first?.duration == 2,
                     "a queued latest run does not inherit the still-active run's start")

        var approvalWithQueuedRun = T3ActivityReducer()
        _ = approvalWithQueuedRun.apply(firstRun)
        let approvalWhileQueued = snapshot(status: "waiting", request: "permission", activeRun: nil,
                                           startedAt: nil, activityStartedAt: "2026-10-06T12:00:00Z",
                                           latestUserAuthoredAt: "2026-10-06T12:09:50Z", latestRunID: "run-2")
        let approvalSecondRunFinished = snapshot(status: "completed", activeRun: nil,
                                                  completedAt: "2026-10-06T12:10:02Z",
                                                  startedAt: "2026-10-06T12:10:00Z",
                                                  latestUserAuthoredAt: "2026-10-06T12:09:50Z",
                                                  latestRunID: "run-2")
        _ = approvalWithQueuedRun.apply(approvalWhileQueued)
        suite.expect(approvalWithQueuedRun.apply(approvalSecondRunFinished).first?.duration == 2,
                     "a queued user message does not make its completion inherit the approval wait duration")

        var coldQueuedRun = T3ActivityReducer()
        _ = coldQueuedRun.apply(approvalWhileQueued)
        suite.expect(coldQueuedRun.apply(approvalSecondRunFinished).first?.duration == 2,
                     "a first snapshot does not bind a queued user's timestamp to the previous activity")

        var reconnectedQueuedRun = T3ActivityReducer()
        _ = reconnectedQueuedRun.apply(firstRun)
        _ = reconnectedQueuedRun.apply([])
        _ = reconnectedQueuedRun.apply(approvalWhileQueued)
        suite.expect(reconnectedQueuedRun.apply(approvalSecondRunFinished).first?.duration == 2,
                     "reconnect does not bind a queued user's timestamp to the previous activity")

        var queuedWake = T3ActivityReducer()
        let originalWork = snapshot(status: "running", activity: "running", startedAt: "2026-10-06T12:00:00Z",
                                    activityStartedAt: "2026-10-06T12:00:00Z",
                                    latestUserAuthoredAt: "2026-10-06T12:00:00Z", latestRunID: "run-1")
        let pendingWake = snapshot(status: "waiting", activeRun: nil, startedAt: nil,
                                   activityStartedAt: "2026-10-06T12:00:00Z",
                                   latestUserAuthoredAt: "2026-10-06T12:00:00Z", latestRunID: "run-2")
        let wakeCompleted = snapshot(status: "completed", activeRun: nil,
                                      completedAt: "2026-10-06T12:10:02Z", startedAt: "2026-10-06T12:10:00Z",
                                      activityStartedAt: nil, latestRunWorkStartedAt: "2026-10-06T12:00:00Z",
                                      latestUserAuthoredAt: "2026-10-06T12:00:00Z",
                                      latestRunID: "run-2")
        _ = queuedWake.apply(originalWork)
        _ = queuedWake.apply(pendingWake)
        suite.expect(queuedWake.apply(wakeCompleted).first?.duration == 602,
                     "a queued wake keeps its original duration even when T3 hides background tasks while queued")

        let coldPendingWake = snapshot(status: "waiting", activity: "waiting", activeRun: nil, startedAt: nil,
                                       activityStartedAt: "2026-10-06T12:00:00Z",
                                       latestUserAuthoredAt: "2026-10-06T12:00:00Z",
                                       latestUserMessageAt: "2026-10-06T12:00:01Z", latestRunID: "run-2")
        let coldWakeCompleted = snapshot(status: "completed", activeRun: nil,
                                          completedAt: "2026-10-06T12:10:02Z",
                                          startedAt: "2026-10-06T12:10:00Z", activityStartedAt: nil,
                                          latestRunWorkStartedAt: "2026-10-06T12:00:00Z",
                                          latestUserAuthoredAt: "2026-10-06T12:00:00Z",
                                          latestUserMessageAt: "2026-10-06T12:10:00Z", latestRunID: "run-2")
        var coldQueuedWake = T3ActivityReducer()
        _ = coldQueuedWake.apply(coldPendingWake)
        suite.expect(coldQueuedWake.apply(coldWakeCompleted).first?.duration == 602,
                     "a cold observer uses the completed run's persisted T3 work start")

        var reconnectedQueuedWake = T3ActivityReducer()
        _ = reconnectedQueuedWake.apply(originalWork)
        _ = reconnectedQueuedWake.apply([])
        _ = reconnectedQueuedWake.apply(coldPendingWake)
        suite.expect(reconnectedQueuedWake.apply(coldWakeCompleted).first?.duration == 602,
                     "a reconnect uses the completed run's persisted T3 work start")

        var cancelledPromptWake = T3ActivityReducer()
        _ = cancelledPromptWake.apply(originalWork)
        let cancelledQueuedPrompt = snapshot(status: "waiting", activity: "waiting", activeRun: nil,
                                             startedAt: nil, activityStartedAt: "2026-10-06T12:00:00Z",
                                             latestUserAuthoredAt: "2026-10-06T12:09:50Z",
                                             latestUserMessageAt: "2026-10-06T12:09:50Z", latestRunID: "run-2")
        let wakeAfterCancellation = snapshot(status: "waiting", activity: "waiting", activeRun: nil,
                                             startedAt: nil, activityStartedAt: "2026-10-06T12:00:00Z",
                                             latestUserAuthoredAt: "2026-10-06T12:09:50Z",
                                             latestUserMessageAt: "2026-10-06T12:09:55Z", latestRunID: "run-3")
        let wakeAfterCancellationCompleted = snapshot(status: "completed", activeRun: nil,
                                                      completedAt: "2026-10-06T12:10:02Z",
                                                      startedAt: "2026-10-06T12:10:00Z", activityStartedAt: nil,
                                                      latestRunWorkStartedAt: "2026-10-06T12:00:00Z",
                                                      latestUserAuthoredAt: "2026-10-06T12:09:50Z",
                                                      latestUserMessageAt: "2026-10-06T12:10:00Z", latestRunID: "run-3")
        _ = cancelledPromptWake.apply(cancelledQueuedPrompt)
        _ = cancelledPromptWake.apply(wakeAfterCancellation)
        suite.expect(cancelledPromptWake.apply(wakeAfterCancellationCompleted).first?.duration == 602,
                     "a wake after a cancelled queued prompt uses T3's persisted work start")

        var queuedUserRunWake = T3ActivityReducer()
        _ = queuedUserRunWake.apply(originalWork)
        let queuedUserRun = snapshot(status: "waiting", activity: "waiting", activeRun: nil,
                                     startedAt: nil, activityStartedAt: "2026-10-06T12:00:00Z",
                                     latestUserAuthoredAt: "2026-10-06T12:09:50Z",
                                     latestUserMessageAt: "2026-10-06T12:09:50Z", latestRunID: "run-2")
        let queuedUserWakeCompleted = snapshot(status: "completed", activeRun: nil,
                                               completedAt: "2026-10-06T12:10:02Z",
                                               startedAt: "2026-10-06T12:10:01Z", activityStartedAt: nil,
                                               latestRunWorkStartedAt: "2026-10-06T12:10:00Z",
                                               latestUserAuthoredAt: "2026-10-06T12:09:50Z",
                                               latestUserMessageAt: "2026-10-06T12:10:00Z",
                                               latestRunID: "run-3")
        _ = queuedUserRunWake.apply(queuedUserRun)
        suite.expect(queuedUserRunWake.apply(queuedUserWakeCompleted).first?.duration == 2,
                     "a wake after a newly started user run uses that run's work start")

        var agentCreatedWake = T3ActivityReducer()
        let agentCreatedRun = snapshot(status: "running", activity: "running", startedAt: "2026-10-06T12:00:00Z",
                                       activityStartedAt: "2026-10-06T12:00:00Z",
                                       latestUserAuthoredAt: nil, latestRunID: "run-1")
        let agentCreatedWakeCompleted = snapshot(status: "completed", activeRun: nil,
                                                 completedAt: "2026-10-06T12:10:02Z",
                                                 startedAt: "2026-10-06T12:10:00Z", activityStartedAt: nil,
                                                 latestRunWorkStartedAt: "2026-10-06T12:00:00Z",
                                                 latestUserAuthoredAt: nil, latestRunID: "run-2")
        _ = agentCreatedWake.apply(agentCreatedRun)
        suite.expect(agentCreatedWake.apply(agentCreatedWakeCompleted).first?.duration == 602,
                     "an agent-created thread uses T3's per-run work start without authored-message metadata")

        var chainedWake = T3ActivityReducer()
        _ = chainedWake.apply(rootWork)
        _ = chainedWake.apply(pendingMonitor)
        let completedWakeWithMonitor = snapshot(status: "completed", activeRun: nil,
                                                completedAt: "2026-10-06T12:05:00Z",
                                                startedAt: "2026-10-06T12:04:55Z", activityStartedAt: nil,
                                                latestRunWorkStartedAt: "2026-10-06T12:00:00Z",
                                                latestRunID: "run-2", backgroundKinds: ["monitor"])
        _ = chainedWake.apply(completedWakeWithMonitor)
        let nextWakeFinished = snapshot(status: "completed", activeRun: nil,
                                         completedAt: "2026-10-06T12:10:00Z",
                                         startedAt: "2026-10-06T12:09:55Z", activityStartedAt: nil,
                                         latestRunWorkStartedAt: "2026-10-06T12:00:00Z",
                                         latestRunID: "run-3")
        suite.expect(chainedWake.apply(nextWakeFinished).first?.duration == 600,
                     "the original activity duration survives a completed wake with another monitor pending")

        var reconnect = T3ActivityReducer()
        _ = reconnect.apply(working)
        _ = reconnect.apply([])
        suite.expect(reconnect.apply(finished).isEmpty,
                     "a completion after a disconnected snapshot is not attributed to stale activity")
        let now = ISO8601DateFormatter().date(from: "2026-10-06T12:03:00Z")!
        suite.expect(T3ActivityPresentation.visible(finished, now: now).count == 1
                        && T3ActivityPresentation.visible(snapshot(status: "idle", activeRun: nil), now: now).isEmpty,
                     "recent terminal threads remain visible while idle threads are omitted")
        let terminalVisibleAt = ISO8601DateFormatter().date(from: "2026-10-06T12:11:59Z")!
        let terminalExpiredAt = ISO8601DateFormatter().date(from: "2026-10-06T12:12:00Z")!
        suite.expect(T3ActivityPresentation.layoutKey([], now: now).isEmpty
                        && T3ActivityPresentation.layoutKey(finished, now: now).count == 1
                        && T3ActivityPresentation.layoutKey(finished, now: terminalVisibleAt).count == 1
                        && T3ActivityPresentation.layoutKey(finished, now: terminalExpiredAt).isEmpty,
                     "terminal-only arrival and expiry change the expanded-page layout key")
    }

    private static func compactPresentation(_ suite: TestSuite) {
        let now = ISO8601DateFormatter().date(from: "2026-10-06T12:03:00Z")!
        func activity(_ id: String, _ state: T3ThreadState, age: TimeInterval = 0) -> T3ThreadActivity {
            let updatedAt = now.addingTimeInterval(-age)
            return T3ThreadActivity(id: id, threadID: id, environmentID: "env-local", environment: "Local Mac",
                                    machine: "MacBook", project: "MowgliNext", title: id, provider: "codex",
                                    model: "gpt-5.4", state: state, startedAt: updatedAt,
                                    completedAt: state == .completed ? updatedAt : nil, updatedAt: updatedAt,
                                    latestRunID: id, latestRunStartedAt: updatedAt, latestRunWorkStartedAt: updatedAt,
                                    activityRunID: state.isActive ? id : nil,
                                    activityRunStartedAt: state.isActive ? updatedAt : nil, backgroundTaskCount: 0)
        }

        let working = activity("working", .working)
        let secondWorking = activity("working-2", .working)
        let waiting = activity("waiting", .waiting)
        let input = activity("input", .waitingForInput)
        let approval = activity("approval", .waitingForApproval)
        let completed = activity("completed", .completed)
        let question = T3ActivityPresentation.compactSummary([working, completed, input], now: now)
        suite.expect(question?.state == .waitingForInput
                        && question?.compactReadout == "T3 · ?",
                     "a pending user question takes priority over completed and working threads")
        suite.expect(T3ActivityPresentation.compactSummary([input, approval, working], now: now)?.state == .waitingForInput,
                     "a user question is the highest-priority compact status")
        suite.expect(!T3ActivityPresentation.allowsCompletionNotice([input, completed])
                        && !T3ActivityPresentation.allowsCompletionNotice([approval, completed]),
                     "a completion notice cannot cover a pending question or approval")
        suite.expect(T3ActivityPresentation.allowsCompletionNotice([waiting, completed]),
                     "ordinary waiting does not suppress a configured completion notice")
        suite.expect(T3ActivityPresentation.compactSummary([approval, waiting, working], now: now)?.state == .waitingForApproval,
                     "approval requests outrank ordinary waiting and work")
        suite.expect(T3ActivityPresentation.compactSummary([waiting, working, completed], now: now)?.state == .completed,
                     "a recent completion is visible briefly alongside waiting and working threads")
        let mixed = T3ActivityPresentation.compactSummary([waiting, working, secondWorking], now: now)
        suite.expect(mixed?.state == .working && mixed?.workingCount == 2
                        && mixed?.compactReadout == "T3 · 2",
                     "ordinary waiting does not hide the count of working T3 threads")
        let mixedAfterFlash = T3ActivityPresentation.compactSummary([waiting, working, completed],
                                                                    now: now.addingTimeInterval(5))
        suite.expect(mixedAfterFlash?.state == .working && mixedAfterFlash?.workingCount == 1,
                     "the working count returns after the completion flash even when another thread is waiting")
        let backgroundWaiting = snapshot(status: "completed", activeRun: nil,
                                         completedAt: "2026-10-06T12:00:00Z", backgroundKinds: ["monitor"])[0]
        let backgroundSummary = T3ActivityPresentation.compactSummary([backgroundWaiting], now: now)
        suite.expect(backgroundSummary?.state == .waiting && backgroundSummary?.workingCount == 0
                        && backgroundSummary?.compactReadout == "T3 · …",
                     "settled background work is visible without inflating the compact working count")

        let completion = T3ActivityPresentation.compactSummary([completed, working], now: now)
        suite.expect(completion?.state == .completed
                        && completion?.compactReadout == "T3 · ✓",
                     "a recent completion gets a short green-check readout while other work continues")
        suite.expect(T3ActivityPresentation.compactCompletionExpiry([completed, working], now: now)
                        == now.addingTimeInterval(T3ActivityPresentation.compactCompletionDuration),
                     "the service can schedule a deterministic refresh at the compact completion deadline")
        let futureCompletion = activity("future-completion", .completed, age: -30)
        suite.expect(T3ActivityPresentation.compactCompletionExpiry([completed, futureCompletion], now: now)
                        == now.addingTimeInterval(T3ActivityPresentation.compactCompletionDuration),
                     "a future-dated remote completion cannot extend the flash deadline")
        let afterCompletion = T3ActivityPresentation.compactSummary([completed, working], now: now.addingTimeInterval(5))
        suite.expect(afterCompletion?.state == .working && afterCompletion?.workingCount == 1
                        && afterCompletion?.compactReadout == "T3 · 1",
                     "the compact island returns to the active count when the completion flash expires")
        suite.expect(T3ActivityPresentation.compactCompletionExpiry([completed, working], now: now.addingTimeInterval(5)) == nil,
                     "expired completion state no longer schedules repeated refreshes")
        let multiple = T3ActivityPresentation.compactSummary([working, secondWorking], now: now)
        suite.expect(multiple?.state == .working && multiple?.workingCount == 2
                        && multiple?.compactReadout == "T3 · 2",
                     "the compact readout shows a concise count for concurrent work")
        suite.expect(T3ActivityPresentation.compactSummary([completed], now: now.addingTimeInterval(5)) == nil,
                     "a completion-only strip disappears after its brief success state")
    }

    private static func endpointValidation(_ suite: TestSuite) {
        let client = T3CodeClient(transport: T3UnusedTransport())
        suite.expect(accepts { try client.validateEndpoint("http://127.0.0.1:3773") },
                     "loopback HTTP endpoints are accepted")
        suite.expect(accepts { try client.validateEndpoint("http://[::1]:3773") },
                     "bracketed IPv6 loopback HTTP endpoints are accepted")
        suite.expect(accepts { try client.validateEndpoint("https://t3.example.test:3773") },
                     "remote HTTPS endpoints are accepted")
        suite.expect(rejects { try client.validateEndpoint("http://t3.example.test:3773") },
                     "remote plain HTTP is rejected")
        suite.expect(rejects { try client.validateEndpoint("https://user:secret@t3.example.test") },
                     "endpoint-embedded credentials are rejected")
        suite.expect(rejects { try client.validateEndpoint("https://t3.example.test/path") },
                     "endpoint paths are rejected")
        let endpoint = try! client.validateEndpoint("https://t3.example.test:3773")
        let otherEndpoint = try! client.validateEndpoint("https://other.example.test:3773")
        suite.expect(T3KeychainCredentialStore.account(endpoint: endpoint, environmentID: "env-local")
                        != T3KeychainCredentialStore.account(endpoint: otherEndpoint, environmentID: "env-local"),
                     "read credentials are bound to their T3 origin")
        suite.expect(T3KeychainCredentialStore.account(endpoint: endpoint, environmentID: "env-local", credentialID: "first")
                        != T3KeychainCredentialStore.account(endpoint: endpoint, environmentID: "env-local", credentialID: "second"),
                     "each pairing receives an isolated Keychain account so delayed cleanup cannot remove a newer token")
        suite.expect(!T3CodeActivityService.shouldStartPolling(featureEnabled: false,
                                                                taskAlreadyRunning: false,
                                                                hasConnection: true),
                     "a saved T3 connection does not poll while AI Agents is disabled")
        suite.expect(T3CodeActivityService.hasSavedConnection(endpoint: "http://127.0.0.1:3773",
                                                               environmentID: "env-local")
                        && !T3CodeActivityService.hasSavedConnection(endpoint: "", environmentID: "env-local")
                        && !T3CodeActivityService.hasSavedConnection(endpoint: "http://127.0.0.1:3773",
                                                                      environmentID: ""),
                     "saved connections remain disconnectable regardless of current token state")
        suite.expect(T3CodeActivityService.shouldStartPolling(featureEnabled: true,
                                                               taskAlreadyRunning: false,
                                                               hasConnection: true)
                        && !T3CodeActivityService.shouldStartPolling(featureEnabled: true,
                                                                     taskAlreadyRunning: true,
                                                                     hasConnection: true)
                        && !T3CodeActivityService.shouldStartPolling(featureEnabled: true,
                                                                     taskAlreadyRunning: false,
                                                                     hasConnection: false),
                     "T3 polling starts only for an enabled feature with one complete connection")
    }

    private static func localization(_ suite: TestSuite) {
        for language in AppLanguage.allCases where language != .enUS {
            let strings = T3CodeStrings(language)
            suite.expect(strings.errors(.pairingRejected) != "The pairing code was rejected or has expired."
                            && strings.errors(.serverUnavailable) != "Could not reach the T3 endpoint.",
                         "T3 connection errors are localized for \(language.rawValue)")
        }
    }

    private static func accepts(_ operation: () throws -> URL) -> Bool { (try? operation()) != nil }
    private static func rejects(_ operation: () throws -> URL) -> Bool {
        do { _ = try operation(); return false } catch { return true }
    }
}

/// Opt-in live acceptance used by the developer when a local T3 pairing code
/// is piped to the test runner. The code and access token are never printed.
enum T3CodeLiveAcceptance {
    static func run(endpoint rawEndpoint: String, pairingCode: String, suite: TestSuite) {
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            defer { finished.signal() }
            let client = T3CodeClient()
            do {
                let endpoint = try client.validateEndpoint(rawEndpoint)
                let (identity, token, expiry) = try await client.pair(endpoint: endpoint, credential: pairingCode)
                let credentials = T3KeychainCredentialStore()
                let credentialID = UUID().uuidString
                let account = T3KeychainCredentialStore.account(endpoint: endpoint, environmentID: identity.id,
                                                                credentialID: credentialID)
                suite.expect(credentials.write(token, account: account),
                             "live T3 read token is saved to the device-only Keychain")
                if let defaults = UserDefaults(suiteName: "vorss.tests.t3-live") {
                    defaults.set(endpoint.absoluteString, forKey: DefaultsKey.notchAgentsT3Endpoint)
                    defaults.set(identity.id, forKey: DefaultsKey.notchAgentsT3Environment)
                    defaults.set(credentialID, forKey: DefaultsKey.notchAgentsT3CredentialID)
                    defaults.set(identity.label, forKey: DefaultsKey.notchAgentsT3Label)
                    defaults.set(identity.machine ?? "", forKey: DefaultsKey.notchAgentsT3Machine)
                    defaults.set(expiry, forKey: DefaultsKey.notchAgentsT3Expiry)
                }
                let snapshot = try await client.fetchSnapshot(endpoint: endpoint, token: token)
                let activities = snapshot.activities(environment: identity)
                suite.expect(!activities.isEmpty, "live T3 shell returns real thread activity")
                suite.expect(activities.contains(where: { $0.state.isActive }),
                             "a real T3 thread is active and available to the Dynamic Island")
                suite.expect(activities.allSatisfy { !$0.title.isEmpty && !$0.environment.isEmpty },
                             "live T3 threads expose usable titles and environment metadata")
            } catch let error as T3CodeConnectionError {
                suite.expect(false, "live T3 integration failed at a protocol boundary: \(error)")
            } catch {
                suite.expect(false, "live T3 integration could not complete")
            }
        }
        finished.wait()
    }
}

private struct T3UnusedTransport: T3CodeHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw T3CodeConnectionError.serverUnavailable
    }
}
