//
//  PresetEditorGremlin.swift
//  surge15Tests
//
//  Property gremlin for RepPresetsEditorView.
//

import Testing
import SwiftUI
import SwiftData
@testable import surge15

// MARK: - Subject

@MainActor
final class PresetEditorSubject: GremlinSubject {

    // ── Declaration ──────────────────────────────────────────────────────────

    static let models: [any PersistentModel.Type] = []

    var rootView: AnyView {
        AnyView(NavigationStack { RepPresetsEditorView() })
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private func currentPresets() -> [Double] {
        guard let raw = UserDefaults.standard.string(forKey: repPresetsKey),
              let stored = JSONStringArray<Double>(rawValue: raw) else {
            return defaultRepPresets
        }
        return stored.values
    }

    // ── Setup ────────────────────────────────────────────────────────────────

    init(context: ModelContext, random: inout GremlinRandom) throws {
        try context.save()
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    func act(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        switch random.int(in: 0..<4) {

        case 0: // tap "Reset" to restore defaults
            guard let resetBtn = scene.buttons(labeled: "Reset").first else {
                return .noop("Reset button not found")
            }
            resetBtn.activate()
            scene.settle()
            return .did("tapped Reset")

        case 1: // type valid rep count into field and tap Add
            let value = random.int(in: 1..<200)
            scene.typeInWindowField(labeled: "Enter value", text: "\(value)")
            if let addBtn = scene.buttons(labeled: "Add").first {
                addBtn.activate()
                scene.settle()
            }
            // dismiss any error alert (duplicate or invalid value)
            if let okBtn = scene.allWindowButtons().first(where: { $0.label == "OK" }) {
                okBtn.activate()
                scene.settle()
            }
            return .did("typed \(value) and tapped Add")

        case 2: // type invalid value and tap Add, then dismiss alert
            let invalid = random.bool() ? "abc" : "-5"
            scene.typeInWindowField(labeled: "Enter value", text: invalid)
            if let addBtn = scene.buttons(labeled: "Add").first {
                addBtn.activate()
                scene.settle()
            }
            if let okBtn = scene.allWindowButtons().first(where: { $0.label == "OK" }) {
                okBtn.activate()
                scene.settle()
            }
            return .did("typed invalid value '\(invalid)' and tapped Add")

        case 3: // external preset manipulation via UserDefaults
            let current = currentPresets()
            if current.count > 1 {
                var updated = current
                let idx = random.int(in: 0..<updated.count)
                updated.remove(at: idx)
                UserDefaults.standard.set(JSONStringArray<Double>(updated).rawValue, forKey: repPresetsKey)
                scene.settle()
                return .did("externally removed preset at index \(idx)")
            }
            scene.settle(2)
            return .noop("only one preset, skipping external removal")

        default:
            scene.settle(2)
            return .noop("wait")
        }
    }

    // ── Invariants ───────────────────────────────────────────────────────────

    func check(scene: GremlinScene, wasDismissed: Bool) -> String? {
        let presets = currentPresets()

        // P1: there must always be at least one preset
        if presets.isEmpty {
            return "P1: no presets remain — all were deleted"
        }

        // P2: each preset value appears as a label in the accessibility tree
        let labels = scene.allLabels()
        for v in presets {
            if !labels.contains(where: { $0.contains("\(Int(v))") }) {
                return "P2: preset \(Int(v)) not visible in list"
            }
        }

        // P3: preset count is always at least 1 (belt-and-suspenders after P1)
        if presets.count < 1 {
            return "P3: preset count dropped below 1"
        }

        return nil
    }
}

// MARK: - Test

@Suite("RepPresetsEditorView gremlin", .serialized)
@MainActor
struct PresetEditorGremlin {

    @Test func invariantsSurviveTheGremlin() {
        falsify("RepPresetsEditorView", subject: PresetEditorSubject.self,
                runs: 60,
                corpus: [])
    }
}
