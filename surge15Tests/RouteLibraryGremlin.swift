//
//  RouteLibraryGremlin.swift
//  surge15Tests
//
//  Property gremlin for RouteLibraryView.
//

import Testing
import SwiftUI
import SwiftData
@testable import surge15

// MARK: - Subject

@MainActor
final class RouteLibrarySubject: GremlinSubject {

    // ── Declaration ──────────────────────────────────────────────────────────

    static let models: [any PersistentModel.Type] = [Route.self, Session.self]

    var rootView: AnyView {
        AnyView(NavigationStack { RouteLibraryView() })
    }

    // ── State (used by act and check) ────────────────────────────────────────

    private let context: ModelContext
    var routes: [Route]
    var sessions: [Session]  // tracks all seeded sessions for P4

    // ── Setup ────────────────────────────────────────────────────────────────

    init(context: ModelContext, random: inout GremlinRandom) throws {
        self.context = context
        routes = context.seedMany(count: 1..<6, using: &random)
        var seeded: [Session] = []
        for route in routes {
            let count = random.int(in: 0..<4)
            for _ in 0..<count {
                let s: Session = context.seed(using: &random)
                s.route = route
                seeded.append(s)
            }
        }
        sessions = seeded
        try context.save()
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    func act(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        switch random.int(in: 0..<7) {

        case 0: // tap a route row to open the rename alert
            let candidates = scene.allElements().filter { el in
                el.isButton && routes.contains(where: { $0.name == el.label })
            }
            return scene.tapRandom(from: candidates, using: &random, noop: "route buttons")

        case 1: // resolve any open alert (rename: Save/Cancel, delete: Delete/Cancel)
            return scene.tapRandomWindowButton(labeled: ["Save", "Cancel", "Delete"], using: &random)

        case 2: // external delete (simulates sync removing a route while view is live)
            guard !routes.isEmpty else { return .noop("no routes") }
            let r = routes[random.int(in: 0..<routes.count)]
            let name = r.name
            let routeSessionIDs = Set(r.sessions.map(\.persistentModelID))
            sessions.removeAll { routeSessionIDs.contains($0.persistentModelID) }
            context.delete(r)
            routes.removeAll { $0.persistentModelID == r.persistentModelID }
            scene.settle()
            return .did("deleted \(name)")

        case 3: // external add (simulates sync delivering a new route)
            let r: Route = context.seed(using: &random)
            routes.append(r)
            scene.settle()
            return .did("externally added \(r.name)")

        case 5: // type a new name into the rename text field if the alert is open
            let typed = random.randomName(prefix: "Route")
            if scene.typeInWindowField(labeled: "Route Name", text: typed) != nil {
                return .did("typed '\(typed)' into rename field")
            }
            return .noop("rename field not open")

        case 4: // UI delete via Edit mode → delete control → alert
            guard let editBtn = scene.buttons(labeled: "Edit").first else {
                return .noop("Edit button not found")
            }
            editBtn.activate()
            scene.settle()

            let deleteControls = scene.allElements().filter { el in
                el.isButton && routes.contains(where: { "Delete \($0.name)" == el.label })
            }
            guard !deleteControls.isEmpty else {
                scene.buttons(labeled: "Done").first?.activate()
                scene.settle()
                return .noop("no delete controls in edit mode")
            }

            let control = deleteControls[random.int(in: 0..<deleteControls.count)]
            let routeName = String(control.label.dropFirst("Delete ".count))
            control.activate()
            scene.settle()

            let result = scene.tapRandomWindowButton(labeled: ["Delete", "Cancel"], using: &random)
            if result.description.contains("Delete") {
                if let r = routes.first(where: { $0.name == routeName }) {
                    let routeSessionIDs = Set(r.sessions.map(\.persistentModelID))
                    sessions.removeAll { routeSessionIDs.contains($0.persistentModelID) }
                }
                routes.removeAll { $0.name == routeName }
            }

            if let doneBtn = scene.buttons(labeled: "Done").first {
                doneBtn.activate()
                scene.settle()
            }

            return result

        default:
            scene.settle(2)
            return .noop("wait")
        }
    }

    // ── Invariants ───────────────────────────────────────────────────────────

    func check(scene: GremlinScene, wasDismissed: Bool) -> String? {
        // P1: no live route has an empty or whitespace-only name
        for r in routes where !r.isDeleted {
            if r.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "P1: route has empty name after settling"
            }
        }

        // P2: every tracked route's name appears somewhere in the accessibility tree
        let labels = scene.allLabels()
        for r in routes {
            if !labels.contains(r.name) {
                return "P2: route '\(r.name)' not visible in list after settling"
            }
        }

        // P3: when not in edit mode, count of route-name buttons matches routes.count
        //     (catches phantom rows, missing rows, or off-by-one after add/delete)
        if scene.buttons(labeled: "Edit").first != nil {
            var expect = [String: Int]()
            for r in routes { expect[r.name, default: 0] += 1 }
            var actual = [String: Int]()
            for el in scene.allElements() where el.isButton {
                if expect[el.label] != nil { actual[el.label, default: 0] += 1 }
            }
            for (name, n) in expect where actual[name, default: 0] < n {
                return "P3: '\(name)' expected \(n) row button(s), found \(actual[name, default: 0])"
            }
        }

        // P4: cascade delete — after any route deletion the context session count
        //     must match our tracking array (sessions removed from tracking when route deleted)
        let contextSessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        if contextSessions.count != sessions.count {
            return "P4: cascade delete failed — context has \(contextSessions.count) sessions, expected \(sessions.count)"
        }

        // P5: all tracked routes still exist in context (rename must not delete-and-recreate)
        let contextRouteIDs = Set((try? context.fetch(FetchDescriptor<Route>()))?.map(\.persistentModelID) ?? [])
        for r in routes {
            if !contextRouteIDs.contains(r.persistentModelID) {
                return "P5: route '\(r.name)' disappeared from context — delete-and-recreate rename bug"
            }
        }

        return nil
    }
}

// MARK: - Test

@Suite("RouteLibraryView gremlin", .serialized)
@MainActor
struct RouteLibraryGremlin {

    @Test func invariantsSurviveTheGremlin() {
        falsify("RouteLibraryView", subject: RouteLibrarySubject.self,
                runs: 60,
                corpus: ["19f2fd02",                                    // empty route name not sanitized on appear
                         "4135899ca449b653d4",                        // empty route name added externally after appear
                         "078602ee80b07b17ae1f1199f19e00b65371"])     // deleted route not removed from tracking array
    }
}
