//
//  RoutePeekSheet.swift
//  surge15
//
//  Compact sheet that appears when the user taps a route's start pin on the
//  home-screen map. Offers two actions: use the route (push detail) or edit it.
//

import SwiftUI

struct RoutePeekSheet: View {
    let route: Route
    let onUse: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(route.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(metadataLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Spacer(minLength: 4)

            VStack(spacing: 10) {
                Button(action: onUse) {
                    Label("Use Route", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button(action: onEdit) {
                    Label("Edit Route", systemImage: "pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
    }

    private var metadataLine: String {
        let distance = Formatters.distance(route.distanceMeters)
        let sessions = "\(route.sessions.count) session\(route.sessions.count == 1 ? "" : "s")"
        let segments = route.segments.count
        if segments > 1 {
            return "\(distance) · \(sessions) · \(segments) segments"
        }
        return "\(distance) · \(sessions)"
    }
}

#Preview {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            RoutePeekSheet(
                route: Route(name: "Backyard 1k"),
                onUse: {},
                onEdit: {}
            )
        }
}
