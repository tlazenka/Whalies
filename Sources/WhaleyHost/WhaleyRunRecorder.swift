#if canImport(UIKit) && canImport(SpriteKit)
import CoreGraphics
import Foundation
import WhaleyCore

@MainActor
public final class WhaleyRunRecorder {
    public static let shared = WhaleyRunRecorder()

    var completed: [WhaleyRecordedRun] = []
    var history: SQLiteRunHistory?
    var current: WhaleyRecordedRun?
    var lastSampleTime: TimeInterval = -.infinity
    var lastLevel: Int?
    private var engineSession: String?
    enum RecordingLifecycle {
        case idle
        case recording
        case finished
    }
    var lifecycle: RecordingLifecycle = .idle
    var appliedAssistance: [Int] = []

    init() { load() }

    public var runCount: Int { completed.count + (current == nil ? 0 : 1) }
    public var recordedRuns: [WhaleyRecordedRun] { completed + (current.map { [$0] } ?? []) }

    public func recentRuns(level: Int, limit: Int = 12) -> [WhaleyRecordedRun] {
        let stored: [WhaleyRecordedRun]
        if let history, let payloads = try? history.payloads(level: level, limit: limit) {
            stored = Array(
                payloads.compactMap { try? JSONDecoder.whaleyRunDecoder.decode(WhaleyRecordedRun.self, from: $0) }
                    .reversed()
            )
        } else {
            stored = Array(completed.filter { $0.level == level }.suffix(limit))
        }
        let active: [WhaleyRecordedRun]
        if let current, current.level == level {
            active = [current]
        } else {
            active = []
        }
        return Array((stored + active).suffix(limit))
    }

    public func flameSuppressionAssessments(level: Int, positions: [CGPoint]) -> [FlameSuppressionAssessment] {
        guard let history else { return [] }
        let activeJSON = current.flatMap { $0.level == level ? try? JSONEncoder().encode($0) : nil }
        return
            (try? history.flameSuppressionAssessments(
                level: level,
                flamePositions: positions.map { (x: Double($0.x), y: Double($0.y)) },
                activeRunJSON: activeJSON
            )) ?? []
    }

    public func insights(level: Int, positions: [CGPoint], query: WhaleyInsightQuery) async -> [WhaleyInsightSummary] {
        guard let history else { return [] }
        let activeJSON = current.flatMap { $0.level == level ? try? JSONEncoder().encode($0) : nil }
        let interpreter = WhaleySQLiteInsightsInterpreter(
            history: history,
            level: level,
            flames: positions.map { (x: Double($0.x), y: Double($0.y)) },
            activeRunJSON: activeJSON
        )
        return (try? await interpreter.execute(query)) ?? []
    }

    public func setAppliedAssistance(_ indices: [Int]) { appliedAssistance = indices.sorted() }

    private func selectEngineSession(level: Int, engineSession: String?) {
        if lastLevel != level || (engineSession != nil && self.engineSession != engineSession) {
            finishCurrent()
            lifecycle = .idle
            lastLevel = level
            self.engineSession = engineSession
        }
    }

    private func beginRun(level: Int) {
        current = WhaleyRecordedRun(
            id: UUID(), level: level, startedAt: .now, endedAt: nil,
            samples: [], inputs: [], assistance: appliedAssistance
        )
        lastSampleTime = -.infinity
        lifecycle = .recording
    }

    /// Events carry their originating native scene identity. Drain them before
    /// observing the current scene so a transition cannot attach old outcomes
    /// to its replacement run. Do not invent a player-position sample here.
    func prepareForEvent(level: Int, engineSession: String?) {
        selectEngineSession(level: level, engineSession: engineSession)
        if case .idle = lifecycle { beginRun(level: level) }
    }

    public func sample(level: Int, time: TimeInterval, position: CGPoint, dead: Bool,
                       completed: Bool = false, engineSession: String? = nil,
                       finishWhenDead: Bool = true) {
        selectEngineSession(level: level, engineSession: engineSession)
        switch lifecycle {
        case .finished where dead || completed:
            return
        case .idle, .finished:
            guard !dead else { return }
            beginRun(level: level)
        case .recording:
            break
        }
        if dead {
            lastSampleTime = time
            current?.samples.append(.init(time: time, x: position.x, y: position.y, dead: true))
            if finishWhenDead {
                finishCurrent()
                lifecycle = .finished
            }
            return
        }
        guard time - lastSampleTime >= 0.1 else { return }
        lastSampleTime = time
        current?.samples.append(.init(time: time, x: position.x, y: position.y, dead: false))
    }

    public func gameplay(
        _ action: WhaleyGameplayEvent.Action,
        time: TimeInterval,
        position: CGPoint,
        objectID: String? = nil
    ) {
        guard current != nil, time.isFinite else { return }
        current?.gameplayEvents
            .append(
                .init(
                    time: time,
                    action: action,
                    x: Double(position.x),
                    y: Double(position.y),
                    objectID: objectID
                )
            )
    }

    public func input(_ phase: WhaleyRawInput.Phase, time: TimeInterval, point: CGPoint) {
        guard current != nil else { return }
        current?.inputs.append(.init(time: time, phase: phase, x: point.x, y: point.y))
    }

    public func finishCurrent() {
        guard var run = current else { return }
        run.endedAt = .now
        completed.append(run)
        current = nil
        if let history {
            do {
                let data = try JSONEncoder.whaleyRunEncoder.encode(run)
                try history.save(id: run.id, level: run.level, endedAt: run.endedAt ?? .now, payload: data)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        } else {
            print("No history available")
        }
    }

    func completeRun() {
        finishCurrent()
        lifecycle = .finished
    }

    func load() {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            assertionFailure("applicationSupportDirectory unavailable")
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = try SQLiteRunHistory(path: directory.appendingPathComponent("whaley-runs.sqlite3").path)
            let payloads = try store.payloads()
            completed = Array(
                payloads.compactMap { try? JSONDecoder.whaleyRunDecoder.decode(WhaleyRecordedRun.self, from: $0) }
                    .reversed()
            )
            history = store
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
}

extension JSONEncoder {
    static var whaleyRunEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
extension JSONDecoder {
    static var whaleyRunDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

#endif
