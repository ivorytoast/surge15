//
//  SurgeIntentGremlin.swift
//  surge15Tests
//
//  Property gremlin for SurgeIntentView.
//

import Testing
import SwiftUI
import SwiftData
@testable import surge15

// MARK: - Subject

@MainActor
final class SurgeIntentSubject: GremlinSubject {

    // ── Declaration ──────────────────────────────────────────────────────────

    static let models: [any PersistentModel.Type] = [Route.self, Plan.self]

    var rootView: AnyView {
        AnyView(SurgeIntentView(onRunRoute: {}, onExecutePlan: {}))
    }

    // ── State (used by act and check) ────────────────────────────────────────

    private let context: ModelContext
    var routes: [Route]
    var plans: [Plan]

    // ── Setup ────────────────────────────────────────────────────────────────

    init(context: ModelContext, random: inout GremlinRandom) throws {
        self.context = context
        routes = context.seedMany(count: 0..<4, using: &random)
        plans = context.seedMany(count: 0..<4, using: &random)
        try context.save()
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    func act(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        switch random.int(in: 0..<5) {

        case 0:
            let r: Route = context.seed(using: &random)
            routes.append(r)
            scene.settle()
            return .did("added route externally")

        case 1:
            guard context.deleteRandom(from: &routes, using: &random) != nil else {
                return .noop("no routes")
            }
            scene.settle()
            return .did("deleted route externally")

        case 2:
            let p: Plan = context.seed(using: &random)
            plans.append(p)
            scene.settle()
            return .did("added plan externally")

        case 3:
            guard context.deleteRandom(from: &plans, using: &random) != nil else {
                return .noop("no plans")
            }
            scene.settle()
            return .did("deleted plan externally")

        default:
            scene.settle(2)
            return .noop("wait")
        }
    }

    // ── Invariants ───────────────────────────────────────────────────────────

    func check(scene: GremlinScene, wasDismissed: Bool) -> String? {
        let labels = scene.allLabels()

        // P1: when routes exist, the badge label must match the count.
        if routes.count > 0 {
            let expected = "\(routes.count) route\(routes.count == 1 ? "" : "s")"
            if !labels.contains(where: { $0.contains(expected) }) {
                return "P1: no label showing \(expected.debugDescription); model has \(routes.count) routes"
            }
        }

        // P2: when plans exist, the badge label must match the count.
        if plans.count > 0 {
            let expected = "\(plans.count) plan\(plans.count == 1 ? "" : "s")"
            if !labels.contains(where: { $0.contains(expected) }) {
                return "P2: no label showing \(expected.debugDescription); model has \(plans.count) plans"
            }
        }

        // P3: when no routes exist, the empty nudge must be visible.
        if routes.isEmpty {
            if !labels.contains(where: { $0.contains("No routes yet") }) {
                return "P3: routes empty but no 'No routes yet' nudge visible"
            }
        }

        // P4: when no plans exist, the empty nudge must be visible.
        if plans.isEmpty {
            if !labels.contains(where: { $0.contains("No plans yet") }) {
                return "P4: plans empty but no 'No plans yet' nudge visible"
            }
        }

        return nil
    }
}

// MARK: - Test

@Suite("SurgeIntentView gremlin", .serialized)
@MainActor
struct SurgeIntentGremlin {

    @Test func invariantsSurviveTheGremlin() {
        falsify("SurgeIntentView", subject: SurgeIntentSubject.self,
                runs: 60,
                corpus: [])
    }
}
