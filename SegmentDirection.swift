//
//  SegmentDirection.swift
//  surge15
//
//  The direction a runner should take at the end of a segment.
//  Stored as the raw string in `RouteSegment.endLabel` for SwiftData friendliness.
//

import SwiftUI

enum SegmentDirection: String, CaseIterable, Hashable {
    case straight  = "Straight"
    case left      = "Left"
    case right     = "Right"
    case around    = "Turnaround"
    case end       = "End"

    /// SF Symbol used inside the D-pad button face (matches the controller direction).
    var padIcon: String {
        switch self {
        case .straight: return "arrow.up"
        case .left:     return "arrow.left"
        case .right:    return "arrow.right"
        case .around:   return "arrow.down"
        case .end:      return "flag.checkered"
        }
    }

    /// SF Symbol used in the in-session full-screen alert overlay.
    var alertIcon: String {
        switch self {
        case .straight: return "arrow.up.circle.fill"
        case .left:     return "arrow.turn.up.left"
        case .right:    return "arrow.turn.up.right"
        case .around:   return "arrow.uturn.backward.circle.fill"
        case .end:      return "flag.checkered.circle.fill"
        }
    }

    /// Big text shown in the in-session alert overlay.
    var alertTitle: String {
        switch self {
        case .straight: return "STRAIGHT"
        case .left:     return "TURN LEFT"
        case .right:    return "TURN RIGHT"
        case .around:   return "TURN AROUND"
        case .end:      return "FINISH"
        }
    }

    /// Mirror the direction for a reverse-direction run (left↔right; turnaround/straight stay the same).
    var reversed: SegmentDirection {
        switch self {
        case .left:     return .right
        case .right:    return .left
        case .straight: return .straight
        case .around:   return .around
        case .end:      return .end
        }
    }

    /// Background color of the in-session alert overlay.
    var alertColor: Color {
        switch self {
        case .straight: return Color.green
        case .end:      return Color.green
        case .left, .right, .around: return Color.orange
        }
    }
}
