//
//  RouteDebugView.swift
//  surge15
//
//  Debug tool: compare raw vs RDP-smoothed route polylines.
//  The epsilon slider writes to AppStorage and is applied app-wide.
//

import SwiftUI
import SwiftData
import MapKit

struct RouteDebugView: View {
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]

    var body: some View {
        List {
            if routes.isEmpty {
                ContentUnavailableView {
                    Label("No Routes", systemImage: "figure.run")
                } description: {
                    Text("Create a route first, then come back here to tune smoothing.")
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(routes) { route in
                    NavigationLink {
                        RouteDebugDetailView(route: route)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(route.name).font(.headline)
                            Text("\(route.sortedDefinitionPoints.count) raw points · \(Formatters.distance(route.distanceMeters))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Route Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RouteDebugDetailView: View {
    @Bindable var route: Route
    @AppStorage(routeSmoothingEpsilonKey) private var epsilon: Double = routeSmoothingEpsilonDefault

    private var rawCoords: [CLLocationCoordinate2D] {
        route.sortedDefinitionPoints.map(\.coordinate)
    }

    private var smoothedCoords: [CLLocationCoordinate2D] {
        route.smoothedCoordinates(epsilon: epsilon)
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
                if rawCoords.count >= 2 {
                    MapPolyline(coordinates: rawCoords)
                        .stroke(Color.red.opacity(0.45), lineWidth: 2)
                }
                if smoothedCoords.count >= 2 {
                    MapPolyline(coordinates: smoothedCoords)
                        .stroke(Color.blue, lineWidth: 3)
                }
                if let start = route.startCoordinate {
                    Annotation("", coordinate: start) {
                        ZStack {
                            Circle().fill(.white).frame(width: 22, height: 22).shadow(radius: 2)
                            Image(systemName: "flag.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.red.opacity(0.5))
                                .frame(width: 20, height: 3)
                            Text("Raw")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }
                        Text("\(rawCoords.count) points")
                            .font(.title3.bold().monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Smoothed")
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue)
                                .frame(width: 20, height: 3)
                        }
                        Text("\(smoothedCoords.count) points")
                            .font(.title3.bold().monospacedDigit())
                    }
                }

                VStack(spacing: 6) {
                    HStack {
                        Text("Smoothing")
                            .font(.callout)
                        Spacer()
                        Text(epsilon == 0 ? "Off" : "\(epsilon, specifier: "%.1f") m epsilon")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $epsilon, in: 0...20, step: 0.5)
                        .tint(.blue)
                    Text("This value is applied everywhere routes are drawn in the app.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .background(.regularMaterial)
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
