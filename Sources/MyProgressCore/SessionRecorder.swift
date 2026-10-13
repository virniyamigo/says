import Foundation

/// Single-session recorder. Long observation gaps are never assumed to be active work.
public struct SessionRecorder {
    private var lastObservation: Date?
    public init() {}
    public mutating func observe(document: inout ProgressDocument, category: ActivityCategory?,
                                 source: TrackingSource = .manual, taskID: UUID? = nil, now: Date) {
        let gap = lastObservation.map { now.timeIntervalSince($0) }
        let continuous = gap.map { $0 >= 0 && $0 <= 5 } ?? false
        if let id = document.activeSessionID,
           let index = document.sessions.firstIndex(where: { $0.id == id }) {
            let session = document.sessions[index]
            let same = category == session.category && source == session.source && taskID == session.taskID
            if continuous && category != nil {
                document.sessions[index].endedAt = max(session.endedAt, now)
            }
            if !same || !continuous || category == nil { document.activeSessionID = nil }
        }
        if let category, document.activeSessionID == nil {
            let session = ActivitySession(category: category, startedAt: now, endedAt: now,
                                          source: source, taskID: taskID)
            document.sessions.append(session)
            document.activeSessionID = session.id
        }
        lastObservation = now
    }
    public mutating func stop(document: inout ProgressDocument, now: Date) {
        if let lastObservation, (0...5).contains(now.timeIntervalSince(lastObservation)),
           let id = document.activeSessionID,
           let index = document.sessions.firstIndex(where: { $0.id == id }) {
            document.sessions[index].endedAt = max(document.sessions[index].endedAt, now)
        }
        document.activeSessionID = nil
        lastObservation = nil
        document.sessions.removeAll { $0.duration == 0 }
    }
}
