//
//  GremlinKit.swift
//  surge15
//
//  Core gremlin primitives used across the entire project.
//  GremlinSeedable conformances live directly alongside each model
//  in Models.swift — one source of truth per type.
//

import Foundation
import SwiftData

// MARK: - GremlinRandomSource

/// Backing source for GremlinRandom. Implemented in the test layer by TapeSource.
protocol GremlinRandomSource: AnyObject {
    func next(_ bound: Int) -> Int
}

// MARK: - GremlinRandom

/// The randomness source passed into seed() and act(). Use the named methods —
/// the byte-sequence mechanics stay hidden in the test layer.
struct GremlinRandom {
    var source: any GremlinRandomSource

    mutating func pick<T>(from options: [T]) -> T {
        guard !options.isEmpty else { fatalError("pick(from:) called with empty array") }
        return options[source.next(options.count)]
    }

    mutating func int(in range: Range<Int>) -> Int {
        guard !range.isEmpty else { return range.lowerBound }
        return range.lowerBound + source.next(range.count)
    }

    mutating func bool(chanceOf trueCount: Int = 1, in total: Int = 2) -> Bool {
        source.next(total) < trueCount
    }

    /// Generates a mix of plausible and adversarial name strings.
    /// `prefix` is used for the normal-looking cases (e.g. "Plan 42").
    mutating func randomName(prefix: String = "Item") -> String {
        pick(from: [
            // normal
            "\(prefix) \(int(in: 1..<100))",
            "\(prefix) \(int(in: 1..<100))",  // weighted heavier toward normal
            // edge cases
            "",
            "  ",
            String(repeating: "x", count: 60),
            // special characters
            "ab&718",
            "name with 'quotes' & <tags>",
            "café / résumé",
            "🏃‍♂️ \(prefix)",
            "\t\n",
        ])
    }
}

// MARK: - GremlinSeedable

/// Conform every SwiftData model to this protocol. The conformance lives next
/// to the model definition in Models.swift so there is one source of truth.
/// Do NOT call context.insert inside seed() — the caller handles insertion.
protocol GremlinSeedable: PersistentModel {
    static func seed(using random: inout GremlinRandom) -> Self
    func mutate(using random: inout GremlinRandom)
}

extension GremlinSeedable {
    func mutate(using random: inout GremlinRandom) {}  // default: no-op
}
