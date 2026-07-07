//
//  CalendarGremlin.swift
//  surge15Tests
//
//  Property gremlin for CalendarHomeView.
//

import Testing
import SwiftUI
import SwiftData
@testable import surge15

// MARK: - GremlinSeedable for SurgeSession

extension SurgeSession: @retroactive GremlinSeedable {
    public static func seed(using random: inout GremlinRandom) -> SurgeSession {
        let daysAgo = random.int(in: 0..<45)
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let dayStart = Calendar.current.startOfDay(for: date)
        return SurgeSession(name: SurgeSession.autoName(for: date), date: dayStart, createdAt: date)
    }
}

// MARK: - Subject

@MainActor
final class CalendarSubject: GremlinSubject {

    // ── Declaration ──────────────────────────────────────────────────────────

    static let models: [any PersistentModel.Type] = [SurgeSession.self, Session.self]

    var rootView: AnyView {
        AnyView(NavigationStack { CalendarHomeView() })
    }

    // ── State (used by act and check) ────────────────────────────────────────

    private let context: ModelContext
    var surgeSessions: [SurgeSession]

    // ── Setup ────────────────────────────────────────────────────────────────

    init(context: ModelContext, random: inout GremlinRandom) throws {
        self.context = context
        surgeSessions = context.seedMany(count: 1..<6, using: &random)
        try context.save()
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    func act(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        switch random.int(in: 0..<5) {

        case 0: // tap prev month
            guard let btn = scene.buttons(labeled: "chevron.left").first else {
                return .noop("prev month button not found")
            }
            btn.activate()
            scene.settle()
            return .did("tapped prev month")

        case 1: // tap next month
            guard let btn = scene.buttons(labeled: "chevron.right").first else {
                return .noop("next month button not found")
            }
            btn.activate()
            scene.settle()
            return .did("tapped next month")

        case 2: // add session externally
            let s: SurgeSession = context.seed(using: &random)
            surgeSessions.append(s)
            scene.settle()
            return .did("added session externally (\(s.name))")

        case 3: // delete session externally
            guard context.deleteRandom(from: &surgeSessions, using: &random) != nil else {
                return .noop("no sessions")
            }
            scene.settle()
            return .did("deleted session externally")

        default: // idle beat — timing gaps are inputs too
            scene.settle(2)
            return .noop("wait")
        }
    }

    // ── Invariants ───────────────────────────────────────────────────────────

    func check(scene: GremlinScene, wasDismissed: Bool) -> String? {
        // P1: the view must render without crashing — allLabels() must be non-empty.
        if scene.allLabels().isEmpty {
            return "P1: allLabels() is empty — CalendarHomeView may have crashed or rendered nothing"
        }

        // P2: the model's session count must match our tracked count.
        //     This verifies that external deletes are reflected correctly.
        let inContext = (try? context.fetch(FetchDescriptor<SurgeSession>()))?.count ?? 0
        let tracked = surgeSessions.filter { !$0.isDeleted }.count
        if inContext != tracked {
            return "P2: context has \(inContext) SurgeSessions but tracked count is \(tracked)"
        }

        return nil
    }
}

// MARK: - Test

@Suite("CalendarHomeView gremlin", .serialized)
@MainActor
struct CalendarGremlin {

    @Test func invariantsSurviveTheGremlin() {
        falsify("CalendarHomeView", subject: CalendarSubject.self,
                runs: 60,
                corpus: [])
    }
}
