//
//  GroupEditGremlin.swift
//  surge15Tests
//
//  Property gremlin for GroupEditView.
//

import Testing
import SwiftUI
import SwiftData
@testable import surge15

// MARK: - Subject

@MainActor
final class GroupEditSubject: GremlinSubject {

    // ── Declaration ──────────────────────────────────────────────────────────

    static let models: [any PersistentModel.Type] = [PlanGroup.self, Plan.self]

    var rootView: AnyView {
        AnyView(NavigationStack { GroupEditView(group: group) })
    }

    // ── State (used by act and check) ────────────────────────────────────────

    let group: PlanGroup
    var plans: [Plan]
    var lastSetName: String? = nil

    // ── Setup ────────────────────────────────────────────────────────────────

    init(context: ModelContext, random: inout GremlinRandom) throws {
        group = context.seed(using: &random)
        plans = context.seedMany(count: 0..<5, using: &random)
        for p in plans where random.bool(chanceOf: 1, in: 3) { p.group = group }
        try context.save()
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    func act(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        switch random.int(in: 0..<6) {

        case 0:
            return scene.tapRandomButton(prefixed: "Plan ", using: &random)

        case 1:
            group.mutate(using: &random)
            lastSetName = group.name  // capture before settle so we can detect binding side-effects
            scene.settle()
            return .did("mutated \(PlanGroup.self)")

        case 2: // gradient change — includes hostile negative values as fault injection
            let hostile = random.bool(chanceOf: 1, in: 4)
            group.cardGradientIndex = hostile
                ? -1 - random.int(in: 0..<3)
                : random.int(in: 0..<planGradients.count)
            // Do NOT settle here — check() runs before the next render so it
            // can catch bad indices before the view subscripts the gradient array.
            return .did("set gradientIndex = \(group.cardGradientIndex)")

        case 3: // delete flow — confirm or cancel via the alert's own window
            guard let d = scene.buttons(labeled: "Delete Group").first else {
                return .noop("delete button not found")
            }
            d.activate()
            scene.settle()
            let result = scene.tapRandomWindowButton(labeled: ["Delete", "Cancel"], using: &random)
            return result.description.contains("Delete") ? .dismissed(result.description) : result

        case 4: // external model mutation while view is live (simulates sync)
            guard !plans.isEmpty else { return .noop("no plans") }
            let p = plans[random.int(in: 0..<plans.count)]
            p.group = random.bool() ? nil : group
            scene.settle()
            return .did("external toggle of \(p.name)")

        default: // idle beat — timing gaps are inputs too
            scene.settle(2)
            return .noop("wait")
        }
    }

    // ── Invariants ───────────────────────────────────────────────────────────

    func check(scene: GremlinScene, wasDismissed: Bool) -> String? {
        // P2/P3: after group deletion, no plans should have been deleted with it.
        // Check this FIRST — accessing a deleted PlanGroup's properties crashes SwiftData.
        if wasDismissed {
            for p in plans where p.isDeleted {
                return "plan \(p.name) was deleted along with the group — footer promised otherwise"
            }
            return nil
        }

        // P1: gradient palette must be non-empty.
        //     The view uses abs(idx) % count so negative indices are safe;
        //     only an empty palette would crash.
        if planGradients.isEmpty {
            return "planGradients is empty — any gradient subscript will crash"
        }

        // P6: the view must not silently modify a non-empty name through its @Bindable binding.
        //     Empty→non-empty is allowed (that's the enforcement kicking in).
        if let expected = lastSetName,
           !expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           group.name != expected {
            return "name was silently modified: expected \(expected.debugDescription), got \(group.name.debugDescription)"
        }

        // P8: after the view has settled, the name must never be empty.
        if group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "group name is empty or whitespace-only after settling — view failed to enforce non-empty"
        }

        // P4: the UI's plan-count label agrees with the model.
        let count = group.plans.count
        let expected = "\(count) plan\(count == 1 ? "" : "s")"
        if !scene.allLabels().contains(where: { $0.contains(expected) }) {
            return "no label showing \(expected.debugDescription); model count = \(count)"
        }

        // P5: selected plan buttons ≤ plans actually assigned to this group.
        let selected = scene.allElements()
            .filter { $0.isButton && $0.label.hasPrefix("Plan ") && $0.traits.contains(.selected) }
        if selected.count > count {
            return "UI shows \(selected.count) checked plans; model has \(count)"
        }

        return nil
    }
}

// MARK: - Test

@Suite("GroupEditView gremlin", .serialized)
@MainActor
struct GroupEditGremlin {

    @Test func invariantsSurviveTheGremlin() {
        falsify("GroupEditView", subject: GroupEditSubject.self,
                runs: 60,
                corpus: ["440c92",                                              // axSnapshot duplicate-counting regression
                         "4d70cb42e6900e6e",                                   // hostile negative gradient index (safe via abs())
                         "a1ef7ab6b79c58a6910cc8f5c714ce94d7f2b8fb8779867e9f"]) // whitespace-only name not caught by isEmpty check
    }
}
