//
//  RoutePeekSheet.swift
//  surge15
//
//  Compact sheet that appears when the user taps a route's start pin on the
//  home-screen map. Offers two actions: use the route (push detail) or edit it.
//

import SwiftUI
import MapKit

struct RoutePeekSheet: View {
    let route: Route
    let onUse: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            routePreviewMap
                .padding(.horizontal, 20)

            HStack(spacing: 10) {
                distanceBox
                goButton
                editButton
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
        .presentationDetents([.height(450)])
        .presentationDragIndicator(.visible)
    }

    private var routePreviewMap: some View {
        Map(initialPosition: .automatic, interactionModes: []) {
            if route.definitionPoints.count >= 2 {
                MapPolyline(coordinates: route.sortedDefinitionPoints.map(\.coordinate))
                    .stroke(Color.blue, lineWidth: 4)
            }
            if let start = route.startCoordinate {
                Annotation("", coordinate: start) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                            .shadow(radius: 1)
                        Image(systemName: "flag.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 9, weight: .heavy))
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private var distanceBox: some View {
        Text(Formatters.distance(route.distanceMeters))
            .font(.system(.title3, design: .rounded, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
    }

    private var goButton: some View {
        Button(action: onUse) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                Text("Go")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var editButton: some View {
        Button(action: onEdit) {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                Text("Edit")
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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
