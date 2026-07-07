//
//  PlanGroupDetailGremlin.swift
//  surge15Tests
//
//  Property gremlin for PlanGroupDetailView.
//

import Testing
import SwiftUI
import SwiftData
@testable import surge15

// MARK: - Subject

@MainActor
final class PlanGroupDetailSubject: GremlinSubject {

    // ── Declaration ──────────────────────────────────────────────────────────

    static let models: [any PersistentModel.Type] = [PlanGroup.self, Plan.self, PlanItem.self, SurgeSession.self]

    var rootView: AnyView {
        AnyView(NavigationStack { PlanGroupDetailView(group: group) })
    }

    // ── State (used by act and check) ────────────────────────────────────────

    private let context: ModelContext
    let group: PlanGroup
    var groupPlans: [Plan]
    var otherPlans: [Plan]

    // ── Setup ────────────────────────────────────────────────────────────────

    init(context: ModelContext, random: inout GremlinRandom) throws {
        self.context = context
        group = context.seed(using: &random)

        var inGroup: [Plan] = []
        for _ in 0..<random.int(in: 1..<4) {
            let p: Plan = context.seed(using: &random)
            p.group = group
            inGroup.append(p)
        }
        groupPlans = inGroup

        var outside: [Plan] = []
        for _ in 0..<random.int(in: 0..<3) {
            let p: Plan = context.seed(using: &random)
            outside.append(p)
        }
        otherPlans = outside

        try context.save()
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    func act(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        switch random.int(in: 0..<6) {

        case 0: // rename a plan in group
            guard !groupPlans.isEmpty else { return .noop("no plans in group") }
            let p = random.pick(from: groupPlans)
            p.name = random.randomName(prefix: "Plan")
            scene.settle()
            return .did("renamed plan in group → \(p.name.debugDescription)")

        case 1: // move plan OUT of group
            guard !groupPlans.isEmpty else { return .noop("no plans in group") }
            let p = random.pick(from: groupPlans)
            groupPlans.removeAll { $0.persistentModelID == p.persistentModelID }
            otherPlans.append(p)
            p.group = nil
            scene.settle()
            return .did("moved plan out of group (\(p.name))")

        case 2: // move plan IN to group
            guard !otherPlans.isEmpty else { return .noop("no plans outside group") }
            let p = random.pick(from: otherPlans)
            otherPlans.removeAll { $0.persistentModelID == p.persistentModelID }
            groupPlans.append(p)
            p.group = group
            scene.settle()
            return .did("moved plan into group (\(p.name))")

        case 3: // delete a plan in group
            guard context.deleteRandom(from: &groupPlans, using: &random) != nil else {
                return .noop("no plans in group")
            }
            scene.settle()
            return .did("deleted plan in group")

        case 4: // toggle group favourite
            group.isFavorite.toggle()
            scene.settle()
            return .did("toggled isFavorite → \(group.isFavorite)")

        default: // idle beat — timing gaps are inputs too
            scene.settle(2)
            return .noop("wait")
        }
    }

    // ── Invariants ───────────────────────────────────────────────────────────

    func check(scene: GremlinScene, wasDismissed: Bool) -> String? {
        scene.popToRoot(via: ["Back"])
        let labels = scene.allLabels()

        // P1: every live plan in groupPlans must appear in the view by name.
        //     NavigationLink rows produce composite accessibility labels
        //     ("Plan Name\nN exercises"), so use substring matching.
        for p in groupPlans where !p.isDeleted {
            if !labels.contains(where: { $0.contains(p.name) }) {
                return "P1: plan '\(p.name)' is in groupPlans but not visible in allLabels()"
            }
        }

        // P2: no plan from otherPlans should be in group.plans.
        //     Checked at the model level — more reliable than UI label scanning
        //     and directly tests the SwiftData relationship invariant.
        let groupPlanIDs = Set(group.plans.map(\.persistentModelID))
        for p in otherPlans where !p.isDeleted {
            if groupPlanIDs.contains(p.persistentModelID) {
                return "P2: plan '\(p.name)' is outside the group but found in group.plans"
            }
        }

        return nil
    }
}

// MARK: - Test

@Suite("PlanGroupDetailView gremlin", .serialized)
@MainActor
struct PlanGroupDetailGremlin {

    @Test func invariantsSurviveTheGremlin() {
        falsify("PlanGroupDetailView", subject: PlanGroupDetailSubject.self,
                runs: 60,
                corpus: ["",                          // empty tape: rename plan at step 0 (P1 composite-label regression)
                         "ea04585670109d3fb1b8a2"])   // empty-named plan not sanitized in PlanGroupDetailView
    }
}
