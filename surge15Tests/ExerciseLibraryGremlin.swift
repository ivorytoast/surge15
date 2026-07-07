//
//  ExerciseLibraryGremlin.swift
//  surge15Tests
//
//  Property gremlin for ExerciseLibraryView.
//

import Testing
import SwiftUI
import SwiftData
@testable import surge15

// MARK: - GremlinSeedable conformance for CustomExercise

extension CustomExercise: @retroactive GremlinSeedable {
    public static func seed(using random: inout GremlinRandom) -> CustomExercise {
        let allMeasures: [WorkoutMeasure] = [.reps, .meters, .yards, .minutes]
        let count = random.int(in: 1..<4)
        let picked = (0..<count).map { _ in allMeasures[random.int(in: 0..<allMeasures.count)] }
        let unique = Array(Set(picked))
        let name = random.randomName(prefix: "Ex")
        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom" : String(name.prefix(18))
        return CustomExercise(name: safeName, iconName: "figure.mixed.cardio", measures: unique.isEmpty ? [.reps] : unique, sortOrder: 0)
    }
}

// MARK: - Subject

@MainActor
final class ExerciseLibrarySubject: GremlinSubject {

    // ── Declaration ──────────────────────────────────────────────────────────

    static let models: [any PersistentModel.Type] = [CustomExercise.self]

    var rootView: AnyView {
        AnyView(NavigationStack { ExerciseLibraryView() })
    }

    // ── State (used by act and check) ────────────────────────────────────────

    private let context: ModelContext
    var exercises: [CustomExercise]

    // ── Setup ────────────────────────────────────────────────────────────────

    init(context: ModelContext, random: inout GremlinRandom) throws {
        self.context = context
        exercises = context.seedMany(count: 0..<3, using: &random)
        try context.save()
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    func act(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        switch random.int(in: 0..<5) {

        case 0: // create exercise via UI — tap "Add Exercise" button, fill the sheet
            guard let addBtn = scene.buttons(labeled: "Add Exercise").first else {
                return .noop("Add Exercise button not found")
            }
            addBtn.activate()
            scene.settle()
            let name = random.randomName(prefix: "Ex")
            let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom" : String(name.prefix(18))
            scene.fillSheet(field: "Exercise Name", text: safeName, confirm: "Save", cancel: "Cancel")
            context.syncNew(into: &exercises)
            return .did("added exercise '\(safeName)' via UI")

        case 1: // rename exercise externally — pick from live exercises, set new name
            guard !exercises.isEmpty else { return .noop("no exercises") }
            let ex = random.pick(from: exercises.filter { !$0.isDeleted })
            guard !ex.isDeleted else { return .noop("picked exercise already deleted") }
            let newName = random.randomName(prefix: "Ex")
            let safeName = newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom" : String(newName.prefix(18))
            ex.name = safeName
            scene.settle()
            return .did("renamed exercise to '\(safeName)'")

        case 2: // delete exercise externally
            context.deleteRandom(from: &exercises, using: &random)
            scene.settle()
            return .did("deleted exercise externally")

        case 3: // add exercise externally (simulates sync)
            let ex: CustomExercise = context.seed(using: &random)
            exercises.append(ex)
            scene.settle()
            return .did("externally added '\(ex.name)'")

        case 4: // toggle a built-in exercise row
            let builtinNames = ["Lunge", "Burpee Broad Jump", "Row", "Wall Balls", "Break"]
            if let el = scene.allElements().first(where: { builtinNames.contains($0.label) }) {
                el.activate()
                scene.settle()
                return .did("tapped built-in row '\(el.label)'")
            }
            scene.settle(2)
            return .noop("no built-in row found")

        default:
            scene.settle(2)
            return .noop("wait")
        }
    }

    // ── Invariants ───────────────────────────────────────────────────────────

    func check(scene: GremlinScene, wasDismissed: Bool) -> String? {
        // P1: every non-deleted tracked exercise has a non-empty measures array
        for e in exercises where !e.isDeleted {
            if e.measures.isEmpty {
                return "P1: exercise '\(e.name)' has empty measures array"
            }
        }

        // P2: every non-deleted tracked exercise appears in the accessibility tree by name
        let labels = scene.allLabels()
        for e in exercises where !e.isDeleted {
            if !labels.contains(where: { $0.contains(e.name) }) {
                return "P2: exercise '\(e.name)' not visible in list after settling"
            }
        }

        // P3: no tracked exercise has an empty name
        for e in exercises where !e.isDeleted {
            if e.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "P3: exercise has empty or whitespace-only name"
            }
        }

        return nil
    }
}

// MARK: - Test

@Suite("ExerciseLibraryView gremlin", .serialized)
@MainActor
struct ExerciseLibraryGremlin {

    @Test func invariantsSurviveTheGremlin() {
        falsify("ExerciseLibraryView", subject: ExerciseLibrarySubject.self,
                runs: 60,
                corpus: [])
    }
}
