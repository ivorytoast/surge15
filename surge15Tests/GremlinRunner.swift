//
//  GremlinRunner.swift
//  surge15Tests
//
//  Test machinery: tape, accessibility snapshot, GremlinSubject protocol, falsify runner.
//  GremlinRandom and GremlinSeedable live in the app (GremlinKit.swift).
//

import Foundation
import SwiftUI
import UIKit
import SwiftData
import Testing
@testable import surge15

// MARK: - Tape

/// A finite byte sequence that drives all random choices deterministically.
/// Exhausted positions return 0 (boring but safe). Hex encoding allows
/// copy-paste replay of any failing run.
struct Tape {
    private(set) var bytes: [UInt8]
    private var pos = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    static func random(length: Int = 64) -> Tape {
        Tape(bytes: (0..<length).map { _ in UInt8.random(in: 0...255) })
    }

    mutating func next(_ bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        guard pos < bytes.count else { return 0 }
        defer { pos += 1 }
        return Int(bytes[pos]) % bound
    }

    var hex: String { bytes.map { String(format: "%02x", $0) }.joined() }

    init?(hex: String) {
        var bs: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            guard let e = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex),
                  let b = UInt8(hex[i..<e], radix: 16) else { return nil }
            bs.append(b); i = e
        }
        self.init(bytes: bs)
    }
}

// MARK: - TapeSource

/// Bridges Tape (a value type) to GremlinRandomSource (a class protocol) so
/// that GremlinRandom — defined in the app target — can be driven by a Tape.
private final class TapeSource: GremlinRandomSource {
    private var tape: Tape
    init(_ tape: Tape) { self.tape = tape }
    func next(_ bound: Int) -> Int { tape.next(bound) }
}

extension GremlinRandom {
    init(tape: Tape) { self.init(source: TapeSource(tape)) }
}

// MARK: - ModelContext seeding helpers

extension ModelContext {
    /// Seed one instance, insert it, and return it. Type is inferred from the call site.
    func seed<T: GremlinSeedable>(using random: inout GremlinRandom) -> T {
        let instance = T.seed(using: &random)
        insert(instance)
        return instance
    }

    /// Seed a random number of instances within `count`, insert each, and return them. Type is inferred from the call site.
    func seedMany<T: GremlinSeedable>(count: Range<Int>, using random: inout GremlinRandom) -> [T] {
        (0..<random.int(in: count)).map { _ in seed(using: &random) }
    }

    /// Append any context objects not yet in `tracking` — call after a UI action
    /// that may have created new model objects the subject doesn't know about yet.
    func syncNew<T: PersistentModel>(into tracking: inout [T]) {
        guard let latest = try? fetch(FetchDescriptor<T>()) else { return }
        for item in latest where !tracking.contains(where: { $0.persistentModelID == item.persistentModelID }) {
            tracking.append(item)
        }
    }

    /// Pick a random item, remove it from `tracking`, delete it from the context,
    /// and return it. Properties remain readable until the next save().
    /// Returns nil if `tracking` is empty.
    @discardableResult
    func deleteRandom<T: PersistentModel>(from tracking: inout [T], using random: inout GremlinRandom) -> T? {
        guard !tracking.isEmpty else { return nil }
        let item = random.pick(from: tracking)
        tracking.removeAll { $0.persistentModelID == item.persistentModelID }
        delete(item)
        return item
    }
}

// MARK: - Accessibility snapshot

struct AXElement {
    let label: String
    let value: String?
    let traits: UIAccessibilityTraits
    let frame: CGRect
    let backing: NSObject

    var isButton: Bool { traits.contains(.button) }
    @discardableResult func activate() -> Bool { backing.accessibilityActivate() }
}

@MainActor
private func axSnapshot(of root: UIView) -> [AXElement] {
    var out: [AXElement] = []
    var seen = Set<ObjectIdentifier>()
    func visit(_ obj: NSObject) {
        let oid = ObjectIdentifier(obj)
        guard !seen.contains(oid) else { return }
        seen.insert(oid)
        if obj.isAccessibilityElement {
            out.append(AXElement(
                label: obj.accessibilityLabel ?? "",
                value: obj.accessibilityValue,
                traits: obj.accessibilityTraits,
                frame: obj.accessibilityFrame,
                backing: obj))
        }
        if let container = obj.accessibilityElements as? [NSObject] { container.forEach(visit) }
        if let view = obj as? UIView { view.subviews.forEach(visit) }
    }
    visit(root)
    return out
}

@MainActor
private func axSnapshotAllWindows() -> [AXElement] {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .flatMap { axSnapshot(of: $0) }
}

// MARK: - GremlinAction

struct GremlinAction {
    let description: String
    let dismissed: Bool

    static func did(_ description: String) -> GremlinAction {
        GremlinAction(description: description, dismissed: false)
    }
    static func dismissed(_ description: String) -> GremlinAction {
        GremlinAction(description: description, dismissed: true)
    }
    static func noop(_ reason: String = "") -> GremlinAction {
        GremlinAction(description: reason.isEmpty ? "noop" : "noop(\(reason))", dismissed: false)
    }
}

// MARK: - GremlinScene

@MainActor
final class GremlinScene {
    private let host: UIHostingController<AnyView>

    fileprivate init(host: UIHostingController<AnyView>) {
        self.host = host
    }

    func settle(_ turns: Int = 4) {
        for _ in 0..<turns {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
        host.view.layoutIfNeeded()
    }

    func allElements() -> [AXElement] { axSnapshot(of: host.view) }
    func allLabels() -> [String] { allElements().map(\.label) }

    func buttons(labeled label: String) -> [AXElement] {
        allElements().filter { $0.isButton && $0.label == label }
    }
    func buttons(prefixed prefix: String) -> [AXElement] {
        allElements().filter { $0.isButton && $0.label.hasPrefix(prefix) }
    }
    func allWindowButtons() -> [AXElement] {
        axSnapshotAllWindows().filter(\.isButton)
    }

    // ── Built-in actions ─────────────────────────────────────────────────────

    /// Tap a random button from `candidates`. Guards empty, activates, settles.
    func tapRandom(from candidates: [AXElement], using random: inout GremlinRandom,
                   noop label: String = "buttons") -> GremlinAction {
        guard !candidates.isEmpty else { return .noop("no \(label) found") }
        let b = candidates[random.int(in: 0..<candidates.count)]
        b.activate()
        settle()
        return .did("tapped \(b.label)")
    }

    /// Tap a random button whose label starts with `prefix`.
    func tapRandomButton(prefixed prefix: String, using random: inout GremlinRandom) -> GremlinAction {
        tapRandom(from: buttons(prefixed: prefix), using: &random, noop: "\(prefix)* button")
    }

    /// Tap a random button across all windows (use for alert buttons).
    func tapRandomWindowButton(labeled options: [String], using random: inout GremlinRandom) -> GremlinAction {
        let candidates = allWindowButtons().filter { options.contains($0.label) }
        return tapRandom(from: candidates, using: &random, noop: options.joined(separator: "/"))
    }

    /// Set the text of a UITextField in any window, identified by its accessibility label.
    /// Returns the text that was set, or nil if the field wasn't found.
    @discardableResult
    func typeInWindowField(labeled fieldLabel: String, text: String) -> String? {
        let elements = axSnapshotAllWindows()
        guard let field = elements.first(where: { !$0.isButton && $0.label == fieldLabel }),
              let tf = field.backing as? UITextField else { return nil }
        tf.text = text
        tf.sendActions(for: .editingChanged)
        settle()
        return text
    }

    /// Mutate an existing model instance using its own randomization logic, then settle.
    func mutate<T: GremlinSeedable>(_ model: T, using random: inout GremlinRandom) -> GremlinAction {
        model.mutate(using: &random)
        settle()
        return .did("mutated \(T.self)")
    }

    // ── Navigation helpers ────────────────────────────────────────────────────

    /// Tap the first element whose label exactly matches, then settle.
    /// Returns true if the element was found. Use for list rows, cards, and other
    /// non-button tappable elements identified by their display name.
    @discardableResult
    func tapElement(labeled label: String) -> Bool {
        guard !label.isEmpty, let el = allElements().first(where: { $0.label == label }) else { return false }
        el.activate()
        settle()
        return true
    }

    /// Tap a tab bar item by label. Tab items may not carry the .button trait on all
    /// iOS versions, so this searches all elements rather than buttons only.
    @discardableResult
    func tapTab(labeled label: String) -> Bool {
        guard let tab = allElements().first(where: { $0.label == label }) else { return false }
        tab.activate()
        settle()
        return true
    }

    /// Tap the first available back button from the candidate labels, then settle.
    /// Returns the label that was tapped, or nil if none was found.
    @discardableResult
    func navigateBack(via labels: [String] = ["Back"]) -> String? {
        for label in labels {
            if let btn = allElements().first(where: { $0.isButton && $0.label == label }) {
                btn.activate()
                settle()
                return label
            }
        }
        return nil
    }

    /// Pop all navigation layers back to root by repeatedly tapping back buttons.
    func popToRoot(via labels: [String] = ["Back"]) {
        var found = true
        while found {
            found = false
            for label in labels {
                if let btn = allElements().first(where: { $0.isButton && $0.label == label }) {
                    btn.activate()
                    settle()
                    found = true
                    break
                }
            }
        }
    }

    /// Tap a toolbar/menu button then pick an item from the resulting menu overlay.
    /// `buttonLabels` are tried in order against all window buttons (Menu buttons
    /// may not appear in the main host view snapshot).
    /// Returns true if both the menu trigger and the item were found and tapped.
    @discardableResult
    func tapMenu(buttonLabels: [String] = ["Add", "plus"], pick itemLabel: String) -> Bool {
        guard let trigger = allWindowButtons().first(where: { buttonLabels.contains($0.label) }) else { return false }
        trigger.activate()
        settle()
        guard let item = allWindowButtons().first(where: { $0.label == itemLabel }) else { return false }
        item.activate()
        settle()
        return true
    }

    /// Type into a named text field in any window, then tap a confirm button.
    /// If the confirm button is not found, taps cancel instead.
    /// Returns true if the confirm button was found and tapped.
    @discardableResult
    func fillSheet(field fieldLabel: String, text: String,
                   confirm confirmLabel: String = "Create",
                   cancel cancelLabel: String = "Cancel") -> Bool {
        typeInWindowField(labeled: fieldLabel, text: text)
        if let btn = allWindowButtons().first(where: { $0.label == confirmLabel }) {
            btn.activate()
            settle()
            return true
        }
        allWindowButtons().first(where: { $0.label == cancelLabel })?.activate()
        settle()
        return false
    }
}

// MARK: - GremlinSubject protocol

// MARK: - GremlinFlow

/// A composable UI interaction flow. Flows can be tested standalone via
/// falsify(_:flow:) and embedded inside a parent GremlinSubject by calling
/// flow.act() and flow.check() directly.
@MainActor
protocol GremlinFlow: AnyObject {
    static var models: [any PersistentModel.Type] { get }
    init(context: ModelContext, random: inout GremlinRandom) throws
    var rootView: AnyView { get }
    func act(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction
    func check(scene: GremlinScene) -> String?
}

// MARK: - GremlinSubject

@MainActor
protocol GremlinSubject: AnyObject {
    static var models: [any PersistentModel.Type] { get }
    init(context: ModelContext, random: inout GremlinRandom) throws
    var rootView: AnyView { get }
    func act(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction
    func check(scene: GremlinScene, wasDismissed: Bool) -> String?
}

// MARK: - falsify

private let corpusDir: URL = {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("gremlin-corpus", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}()

@MainActor
func falsify<S: GremlinSubject>(
    _ name: String,
    subject: S.Type,
    runs: Int = 60,
    corpus: [String] = []
) {
    func runOnce(_ bytes: [UInt8]) -> String? {
        try? Data(bytes).write(to: corpusDir.appendingPathComponent("last-run.tape"))

        UIView.setAnimationsEnabled(false)
        var random = GremlinRandom(tape: Tape(bytes: bytes))

        let container: ModelContainer
        do {
            let schema = Schema(S.models)
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try ModelContainer(for: schema, configurations: config)
        } catch { return "ModelContainer setup failed: \(error)" }

        let s: S
        do { s = try S(context: container.mainContext, random: &random) }
        catch { return "subject init failed: \(error)" }

        let rootWithEnv = AnyView(s.rootView
            .modelContainer(container)
            .transaction { $0.disablesAnimations = true })
        let host = UIHostingController(rootView: rootWithEnv)

        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.makeKeyAndVisible()

        let scene = GremlinScene(host: host)
        scene.settle()

        defer {
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
            window.isHidden = true
            window.rootViewController = nil
        }

        var dismissed = false
        let steps = 2 + random.int(in: 0..<8)
        var log: [String] = []

        for i in 0..<steps {
            let action = s.act(scene: scene, random: &random)
            log.append(action.description)
            if action.dismissed { dismissed = true }
            if let violation = s.check(scene: scene, wasDismissed: dismissed) {
                return "step \(i) [\(action.description)]: \(violation)\n  story: \(log.joined(separator: " → "))"
            }
            if dismissed { break }
        }
        return nil
    }

    for hex in corpus {
        guard let t = Tape(hex: hex) else { continue }
        if let msg = runOnce(t.bytes) {
            Issue.record("✗ \(name) FALSIFIED (corpus replay)\n  \(msg)\n  tape: \(hex)")
            return
        }
    }

    for run in 0..<runs {
        let fresh = Tape.random()
        guard runOnce(fresh.bytes) != nil else { continue }

        var best = fresh.bytes
        var chunk = max(best.count / 2, 1)
        while chunk >= 1 {
            var start = 0
            while start + chunk <= best.count {
                var cand = best
                cand.removeSubrange(start..<(start + chunk))
                if runOnce(cand) != nil { best = cand } else { start += chunk }
            }
            chunk /= 2
        }
        let msg = runOnce(best) ?? "(?)"
        try? Data(best).write(to: corpusDir.appendingPathComponent(
            "\(name)-\(Tape(bytes: best).hex.prefix(8)).tape"))
        Issue.record("""
            ✗ \(name) FALSIFIED (run \(run), shrunk \(fresh.bytes.count)→\(best.count) bytes)
              \(msg)
              replay: add "\(Tape(bytes: best).hex)" to corpus
              corpus: \(corpusDir.path)
            """)
        return
    }
}

// MARK: - GremlinFlow standalone runner

/// Thin adapter so a GremlinFlow can be driven by the existing falsify() machinery.
@MainActor
private final class FlowAdapter<F: GremlinFlow>: GremlinSubject {
    static var models: [any PersistentModel.Type] { F.models }
    private let flow: F
    required init(context: ModelContext, random: inout GremlinRandom) throws {
        flow = try F(context: context, random: &random)
    }
    var rootView: AnyView { flow.rootView }
    func act(scene: GremlinScene, random: inout GremlinRandom) -> GremlinAction {
        flow.act(scene: scene, random: &random)
    }
    func check(scene: GremlinScene, wasDismissed: Bool) -> String? {
        flow.check(scene: scene)
    }
}

/// Run a GremlinFlow standalone — identical to falsify(_:subject:) but wired
/// through FlowAdapter so flows need no knowledge of wasDismissed.
@MainActor
func falsify<F: GremlinFlow>(
    _ name: String,
    flow: F.Type,
    runs: Int = 60,
    corpus: [String] = []
) {
    falsify(name, subject: FlowAdapter<F>.self, runs: runs, corpus: corpus)
}
