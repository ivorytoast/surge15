//
//  CreatePlanFlow.swift
//  surge15Tests
//
//  Composable GremlinFlow for the plan creation UI.
//  Can be tested standalone or embedded in a parent GremlinSubject.
//

import Testing
import SwiftUI
import SwiftData
@testable import surge15

// MARK: - Flow

@MainActor
final class CreatePlanFlow: GremlinFlow {

    // ── Declaration ──────────────────────────────────────────────────────────

    static let models: [any PersistentModel.Type] = [Plan.self, PlanItem.self, PlanGroup.self]

    // Standalone root: PlansHomeView already contains its own NavigationStack
    var rootView: AnyView { AnyView(PlansHomeView()) }

    // ── State ────────────────────────────────────────────────────────────────

    let context: ModelContext
    var plans: [Plan]
    var groups: [PlanGroup]

    // ── Setup ────────────────────────────────────────────────────────────────

    init(context: ModelContext, random: inout GremlinRandom) throws {
        self.context = context
        groups = context.seedMany(count: 0..<3, using: &random)
        plans  = context.seedMany(count: 0..<4, using: &random)
        for p in plans where !groups.isEmpty && random.bool(chanceOf: 1, in: 3) {
            p.group = random.pick(from: groups)
        }
        try context.save()
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    func act(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        switch random.int(in: 0..<6) {
        case 0: return createPlanViaUI(scene: scene, random: &random)
        case 1: return deletePlanExternally(random: &random)
        case 2: return movePlanExternally(scene: scene, random: &random)
        case 3: return renamePlanExternally(scene: scene, random: &random)
        case 4: return addGroupExternally(scene: scene, random: &random)
        default: scene.settle(2); return .noop("wait")
        }
    }

    // ── Invariants ───────────────────────────────────────────────────────────

    func check(scene: GremlinScene) -> String? {
        // P1: no tracked plan has an empty name
        for p in plans where p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "P1: plan has empty name after settling"
        }

        // Pop any pushed view before checking list visibility
        scene.popToRoot(via: ["Back"])

        // P2: every plan visible somewhere in PlansHomeView
        let labels = scene.allLabels()
        for p in plans where !labels.contains(where: { $0.contains(p.name) }) {
            return "P2: plan '\(p.name)' missing from PlansHomeView"
        }

        // P3: single-parent — each plan appears in at most one group's plans array
        for p in plans {
            let ownerCount = groups.filter { g in
                g.plans.contains(where: { $0.persistentModelID == p.persistentModelID })
            }.count
            if ownerCount > 1 {
                return "P3: plan '\(p.name)' appears in \(ownerCount) groups — single-parent violated"
            }
        }

        return nil
    }

    // ── Individual actions ────────────────────────────────────────────────────

    private func createPlanViaUI(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        // Ensure Plans tab is active — no-op when running standalone (no tab bar present)
        scene.tapTab(labeled: "Plans")
        // Open CreatePlanView via the "+" menu
        guard scene.tapMenu(pick: "New Plan") else { return .noop("New Plan menu item not found") }

        // Tap a random exercise type chip (shortName labels: Run, Lunge, BBJ, Row, W.Ball, Break)
        let typeLabel = random.pick(from: WorkoutItemType.allCases.map(\.shortName))
        scene.allWindowButtons().first(where: { $0.label == typeLabel })?.activate()
        scene.settle()

        // Add the chosen exercise to the draft list
        guard let addBtn = scene.allWindowButtons().first(where: { $0.label == "Add to Plan" }) else {
            scene.allWindowButtons().first(where: { $0.label == "Cancel" })?.activate()
            scene.settle()
            return .noop("Add to Plan button not found")
        }
        addBtn.activate()
        scene.settle()

        // Save is now enabled (draftItems is non-empty)
        guard let saveBtn = scene.allWindowButtons().first(where: { $0.label == "Save" }) else {
            scene.allWindowButtons().first(where: { $0.label == "Cancel" })?.activate()
            scene.settle()
            return .noop("Save button not found after adding exercise")
        }
        saveBtn.activate()
        scene.settle()

        // Plan details sheet: fill name, confirm with "Create", back-out with "Back"
        let rawName = random.randomName(prefix: "Plan")
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Plan" : rawName
        guard scene.fillSheet(field: "Plan Name", text: name, confirm: "Create", cancel: "Back") else {
            return .noop("Plan details sheet not found")
        }

        context.syncNew(into: &plans)
        return .did("created plan '\(name)' via UI")
    }

    private func deletePlanExternally(random: inout GremlinRandom) -> GremlinAction {
        guard let p = context.deleteRandom(from: &plans, using: &random) else { return .noop("no plans") }
        return .did("externally deleted '\(p.name)'")
    }

    private func movePlanExternally(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        guard !plans.isEmpty else { return .noop("no plans") }
        let p = random.pick(from: plans)
        let old = p.group?.name ?? "none"
        // Filter deleted groups — a parent subject may have deleted some via its own act()
        let liveGroups = groups.filter { !$0.isDeleted }
        p.group = (liveGroups.isEmpty || random.bool()) ? nil : random.pick(from: liveGroups)
        scene.settle()
        return .did("moved '\(p.name)' from '\(old)' to '\(p.group?.name ?? "none")'")
    }

    private func renamePlanExternally(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        guard !plans.isEmpty else { return .noop("no plans") }
        let p = random.pick(from: plans)
        let old = p.name
        p.name = random.randomName(prefix: "Plan")
        scene.settle()
        return .did("externally renamed '\(old)' → '\(p.name)'")
    }

    private func addGroupExternally(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        let g: PlanGroup = context.seed(using: &random)
        groups.append(g)
        scene.settle()  // give the view time to run sanitizeGroupNames() on the new insertion
        return .did("externally added group '\(g.name)'")
    }
}

// MARK: - Standalone test

@Suite("CreatePlan flow", .serialized)
@MainActor
struct CreatePlanFlowTests {

    @Test func invariantsSurviveTheGremlin() {
        falsify("CreatePlanFlow", flow: CreatePlanFlow.self, runs: 60,
                corpus: ["d2131a4234",           // empty plan name not sanitized on appear
                         "8a8d65ef51fa97b01cada416"])  // addGroupExternally missing scene.settle()
    }
}
