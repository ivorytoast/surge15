//
//  PlanGroupFlowGremlin.swift
//  surge15Tests
//
//  Flow gremlin: Plans home ↔ Settings/Groups cross-view consistency.
//  Tests that groups and plans created, renamed, or deleted in one view are
//  correctly reflected in the other — the primary source of cross-view bugs.
//
//  `CreatePlanFlow` is embedded here so plan-creation chaos is generated
//  alongside group lifecycle chaos in the same run.
//

import Testing
import SwiftUI
import SwiftData
@testable import surge15

// MARK: - Subject

@MainActor
final class PlanGroupFlowSubject: GremlinSubject {

    // ── Declaration ──────────────────────────────────────────────────────────

    static let models: [any PersistentModel.Type] = [PlanGroup.self, Plan.self, PlanItem.self]

    var rootView: AnyView {
        AnyView(
            TabView {
                PlansHomeView()
                    .tabItem { Label("Plans", systemImage: "list.clipboard") }
                NavigationStack { GroupLibraryView() }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        )
    }

    // ── State ────────────────────────────────────────────────────────────────

    private let context: ModelContext
    // Embedded flow handles plan creation complexity and tracks its own plans/groups subset
    private let planFlow: CreatePlanFlow
    // Parent tracks all groups for cross-tab consistency checks (P2/P3)
    var groups: [PlanGroup]

    // ── Setup ────────────────────────────────────────────────────────────────

    init(context: ModelContext, random: inout GremlinRandom) throws {
        self.context = context
        // Flow seeds its own groups and plans; must come first so its groups are in context
        planFlow = try CreatePlanFlow(context: context, random: &random)
        // Parent adds a few more groups on top for additional variety
        let extra: [PlanGroup] = context.seedMany(count: 0..<2, using: &random)
        // Start tracking all groups: flow's seed + parent's extra
        groups = planFlow.groups + extra
        try context.save()
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    func act(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        switch random.int(in: 0..<12) {
        case 0: scene.tapTab(labeled: "Plans");    return .did("switched to Plans tab")
        case 1: scene.tapTab(labeled: "Settings"); return .did("switched to Settings tab")
        case 2: return createGroupViaUI(scene: scene, random: &random)
        case 3: return openGroupFromSettings(scene: scene, random: &random)
        case 4: return navigateBack(scene: scene)
        case 5: return deleteGroupViaUI(scene: scene, random: &random)
        case 6: return renameExternally(scene: scene, random: &random)
        case 7: return deleteExternally(random: &random)
        case 8...10: return planFlow.act(scene: scene, random: &random)
        default: scene.settle(2); return .noop("wait")
        }
    }

    // ── Individual actions ────────────────────────────────────────────────────

    private func createGroupViaUI(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        scene.tapTab(labeled: "Plans")
        guard scene.tapMenu(pick: "New Group") else { return .noop("New Group menu item not found") }
        let rawName = random.randomName(prefix: "Group")
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Group" : rawName
        guard scene.fillSheet(field: "Group Name", text: name) else {
            return .noop("Create button not found — sheet cancelled")
        }
        context.syncNew(into: &groups)
        return .did("created '\(name)' via UI")
    }

    private func openGroupFromSettings(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        scene.tapTab(labeled: "Settings")
        guard !groups.isEmpty else { return .noop("no groups") }
        let g = random.pick(from: groups)
        guard scene.tapElement(labeled: g.name) else {
            return .noop("group row '\(g.name)' not found in list")
        }
        return .did("opened '\(g.name)' in GroupEditView")
    }

    private func navigateBack(scene: GremlinScene) -> GremlinAction {
        guard let label = scene.navigateBack(via: ["Groups", "Back"]) else {
            return .noop("no back button found")
        }
        return .did("navigated back via '\(label)'")
    }

    private func deleteGroupViaUI(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        scene.tapTab(labeled: "Settings")
        guard !groups.isEmpty else { return .noop("no groups") }
        let g = random.pick(from: groups)
        guard scene.tapElement(labeled: g.name) else { return .noop("group row not found") }
        guard let deleteBtn = scene.buttons(labeled: "Delete Group").first else {
            scene.tapTab(labeled: "Settings")
            return .noop("Delete Group button not found")
        }
        deleteBtn.activate()
        scene.settle()
        let result = scene.tapRandomWindowButton(labeled: ["Delete", "Cancel"], using: &random)
        if result.description.contains("Delete") {
            groups.removeAll { $0.persistentModelID == g.persistentModelID }
            return .dismissed(result.description)
        }
        scene.tapTab(labeled: "Settings")
        return result
    }

    private func renameExternally(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        guard !groups.isEmpty else { return .noop("no groups") }
        let g = random.pick(from: groups)
        let old = g.name
        g.name = random.randomName(prefix: "Group")
        scene.settle()
        return .did("externally renamed '\(old)' → '\(g.name)'")
    }

    private func deleteExternally(random: inout GremlinRandom) -> GremlinAction {
        guard let g = context.deleteRandom(from: &groups, using: &random) else { return .noop("no groups") }
        return .did("externally deleted '\(g.name)'")
    }

    // ── Invariants ───────────────────────────────────────────────────────────

    func check(scene: GremlinScene, wasDismissed: Bool) -> String? {
        // Pick up groups added by the flow's addGroupExternally or createGroupViaUI
        context.syncNew(into: &groups)

        // P1: no tracked group has an empty name
        for g in groups where g.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "P1: group has empty name after settling"
        }

        // Delegate plan invariants to the embedded flow.
        // The flow pops to root and verifies plan visibility on the Plans tab.
        scene.tapTab(labeled: "Plans")
        if let violation = planFlow.check(scene: scene) { return violation }

        // P2: every tracked live group visible in PlansHomeView (still on Plans tab)
        let plansLabels = scene.allLabels()
        for g in groups where !g.isDeleted && !plansLabels.contains(where: { $0.contains(g.name) }) {
            return "P2: group '\(g.name)' missing from PlansHomeView"
        }

        // P3: every tracked live group visible in GroupLibraryView
        scene.tapTab(labeled: "Settings")
        let settingsLabels = scene.allLabels()
        for g in groups where !g.isDeleted && !settingsLabels.contains(where: { $0.contains(g.name) }) {
            return "P3: group '\(g.name)' missing from GroupLibraryView"
        }

        return nil
    }
}

// MARK: - Test

@Suite("PlanGroup flow gremlin", .serialized)
@MainActor
struct PlanGroupFlowGremlin {

    @Test func invariantsSurviveTheGremlin() {
        falsify("PlanGroupFlow", subject: PlanGroupFlowSubject.self,
                runs: 60,
                corpus: ["ba82da4f",                           // empty group name not sanitized on appear
                         "cfbcd0c3ba2e5f16016b3f84349067fd",  // whitespace name from external rename not caught
                         "d2131a4234",                        // empty plan name not sanitized on appear
                         "8a8d65ef51fa97b01cada416"])         // addGroupExternally missing scene.settle()
    }
}
