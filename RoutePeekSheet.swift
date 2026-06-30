//
//  RoutePeekSheet.swift
//  surge15
//
//  Floating card shown when the user taps a route pin on the map.
//  User picks laps/meters and target here, then taps Go.
//

import SwiftUI
import MapKit

struct RoutePeekSheet: View {
    let route: Route
    let onUse: (SessionMode, Double) -> Void


    @State private var sessionMode: SessionMode = .laps
    @State private var targetLaps: Int = 3
    @State private var targetMeters: Double = 10

    @State private var isSharingRoute = false
    @State private var shareItem: ShareItem? = nil
    @State private var shareError: String? = nil

    private let lapPresets    = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 20, 25, 50, 100]
    private let meterPresets: [Double] = [1, 5, 10, 20, 40, 50, 75, 100, 125, 150, 200, 250,
                                          300, 350, 400, 450, 500, 550, 600, 650, 700, 750,
                                          800, 850, 900, 950, 1000]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(route.name)
                    .font(.headline)
                Spacer()
                if isSharingRoute {
                    ProgressView().scaleEffect(0.8)
                        .padding(.trailing, 4)
                } else {
                    Button {
                        isSharingRoute = true
                        Task {
                            do {
                                let code = try await RouteShareService.share(route)
                                shareItem = ShareItem(text: RouteShareService.shareMessage(code: code))
                            } catch {
                                shareError = (error as? RouteShareService.ShareError)?.errorDescription
                                    ?? "Something went wrong."
                            }
                            isSharingRoute = false
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
                Button {
                    route.isFavorite.toggle()
                } label: {
                    Image(systemName: route.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 20))
                        .foregroundStyle(route.isFavorite ? .pink : Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
            }

            routePreviewMap

            HStack(spacing: 10) {
                distanceBox
                goButton
            }

            pickerPanel
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.25), radius: 28, y: 10)
        .padding(.horizontal, 20)
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.text])
        }
        .alert("Couldn't Share Route", isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: {
            Text(shareError ?? "")
        }
    }

    // MARK: - Map

    private var routePreviewMap: some View {
        Map(initialPosition: .automatic, interactionModes: []) {
            if route.definitionPoints.count >= 2 {
                MapPolyline(coordinates: route.smoothedCoordinates(epsilon: routeDisplayEpsilon))
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
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Buttons

    private var distanceBox: some View {
        Text(Formatters.distance(route.distanceMeters))
            .font(.system(.title3, design: .rounded, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
    }

    private var goButton: some View {
        Button {
            let target = sessionMode == .laps ? Double(targetLaps) : targetMeters
            onUse(sessionMode, target)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                Text("Go")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Picker panel

    private var pickerPanel: some View {
        VStack(spacing: 10) {
            Picker("Mode", selection: $sessionMode) {
                Text("Laps").tag(SessionMode.laps)
                Text("Meters").tag(SessionMode.distance)
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if sessionMode == .laps {
                        ForEach(lapPresets, id: \.self) { n in
                            chip(label: "\(n)", isSelected: targetLaps == n) {
                                targetLaps = n
                            }
                        }
                    } else {
                        ForEach(meterPresets, id: \.self) { m in
                            chip(label: Formatters.distance(m), isSelected: targetMeters == m) {
                                targetMeters = m
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.leading, 2)
            }
            .mask(
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 36)
                }
            )
        }
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.callout.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : Color(.systemFill), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        RoutePeekSheet(route: Route(name: "Backyard 1k")) { _, _ in }
    }
}
