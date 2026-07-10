//
//  PlanDetailGremlin.swift
//  surge15Tests
//
//  Property gremlin for PlanDetailView.
//

import Testing
import SwiftUI
import SwiftData
@testable import surge15

// MARK: - Subject

@MainActor
final class PlanDetailSubject: GremlinSubject {

    // ── Declaration ──────────────────────────────────────────────────────────

    static let models: [any PersistentModel.Type] = [Plan.self, PlanItem.self, Route.self]

    var rootView: AnyView {
        AnyView(NavigationStack { PlanDetailView(plan: plan) })
    }

    // ── State (used by act and check) ────────────────────────────────────────

    private let context: ModelContext
    let plan: Plan
    var items: [PlanItem]
    var routes: [Route]

    // ── Setup ────────────────────────────────────────────────────────────────

    init(context: ModelContext, random: inout GremlinRandom) throws {
        self.context = context
        plan = context.seed(using: &random)

        var seededItems: [PlanItem] = []
        for i in 0..<random.int(in: 0..<4) {
            let type = random.pick(from: WorkoutItemType.allCases)
            let measure = random.pick(from: type.availableMeasures)
            let item = PlanItem(order: i, workoutType: type, measure: measure,
                                targetValue: Double(random.int(in: 1..<50)))
            item.plan = plan
            context.insert(item)
            seededItems.append(item)
        }
        items = seededItems
        routes = context.seedMany(count: 0..<3, using: &random)
        try context.save()
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    func act(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        switch random.int(in: 0..<6) {

        case 0:
            let type = random.pick(from: WorkoutItemType.allCases)
            let measure = random.pick(from: type.availableMeasures)
            let item = PlanItem(order: items.count, workoutType: type, measure: measure,
                                targetValue: Double(random.int(in: 1..<50)))
            item.plan = plan
            context.insert(item)
            items.append(item)
            scene.settle()
            return .did("added item externally (\(type.displayName))")

        case 1:
            guard context.deleteRandom(from: &items, using: &random) != nil else {
                return .noop("no items")
            }
            scene.settle()
            return .did("deleted item externally")

        case 2:
            let r: Route = context.seed(using: &random)
            routes.append(r)
            scene.settle()
            return .did("added route externally")

        case 3:
            guard context.deleteRandom(from: &routes, using: &random) != nil else {
                return .noop("no routes")
            }
            scene.settle()
            return .did("deleted route externally")

        case 4:
            plan.isFavorite.toggle()
            scene.settle()
            return .did("toggled isFavorite externally → \(plan.isFavorite)")

        default:
            scene.settle(2)
            return .noop("wait")
        }
    }

    // ── Invariants ───────────────────────────────────────────────────────────

    func check(scene: GremlinScene, wasDismissed: Bool) -> String? {
        let labels = scene.allLabels()

        // P1: the "Exercises  ·  N" section header must reflect the live item count.
        let count = items.filter { !$0.isDeleted }.count
        if !labels.contains(where: { $0.contains("Exercises") && $0.contains("\(count)") }) {
            return "P1: no label showing both 'Exercises' and '\(count)'; model item count = \(count)"
        }

        // P2: every live item's workout type display name must appear somewhere in the UI.
        for item in items where !item.isDeleted {
            let name = item.workoutType.displayName
            if !labels.contains(where: { $0.contains(name) }) {
                return "P2: item '\(name)' not visible in allLabels()"
            }
        }

        return nil
    }
}

// MARK: - Test

@Suite("PlanDetailView gremlin", .serialized)
@MainActor
struct PlanDetailGremlin {

    @Test func invariantsSurviveTheGremlin() {
        falsify("PlanDetailView", subject: PlanDetailSubject.self,
                runs: 60,
                corpus: [])
    }
}
