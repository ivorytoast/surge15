//
//  SurgeIntentView.swift
//  surge15
//

import SwiftUI
import SwiftData

// MARK: - Surge intent chooser

struct SurgeIntentView: View {
    let onRunRoute: () -> Void
    let onExecutePlan: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Query private var routes: [Route]
    @Query private var plans: [Plan]

    @State private var quote: String = ""

    private var isLight: Bool { colorScheme == .light }
    private var pageBackground: Color {
        isLight ? Color(red: 0.961, green: 0.973, blue: 0.992) : Color(red: 0.027, green: 0.039, blue: 0.094)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("\"\(quote)\"")
                .font(.subheadline.italic())
                .foregroundStyle(isLight ? Color(red: 0.059, green: 0.090, blue: 0.165) : .white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.bottom, 14)

            intentTile(
                title: "Run a Route",
                subtitle: "GPS-tracked laps on your personal loop",
                emptyNudge: "No routes yet — go create one",
                icon: "figure.run",
                count: routes.count,
                countLabel: "route",
                // #1e3a8a → #2563eb  Navy → Primary Blue
                gradient: LinearGradient(
                    colors: [Color(red: 0.118, green: 0.227, blue: 0.541), Color(red: 0.145, green: 0.388, blue: 0.922)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                action: onRunRoute
            )
            .padding(.bottom, 10)
            intentTile(
                title: "Execute a Plan",
                subtitle: "Work through your structured workout",
                emptyNudge: "No plans yet — go create one",
                icon: "bolt.fill",
                count: plans.count,
                countLabel: "plan",
                // #15235a → #60a5fa  Mid Navy → Light Blue
                gradient: LinearGradient(
                    colors: [Color(red: 0.082, green: 0.137, blue: 0.353), Color(red: 0.376, green: 0.647, blue: 0.980)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                action: onExecutePlan
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(320)])
        .presentationBackground(pageBackground)
        .onAppear {
            quote = Quotes.surgeIntent.randomElement() ?? ""
        }
    }

    private func intentTile(
        title: String,
        subtitle: String,
        emptyNudge: String,
        icon: String,
        count: Int,
        countLabel: String,
        gradient: LinearGradient,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                ZStack(alignment: .bottomLeading) {
                    gradient
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.4)],
                        startPoint: .top, endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            Image(systemName: icon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            if count > 0 {
                                Text("\(count) \(countLabel)\(count == 1 ? "" : "s")")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.white.opacity(0.2), in: Capsule())
                            } else {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        Spacer()
                        Text(title)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)

            if count == 0 {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(emptyNudge)
                        Image(systemName: "arrow.right")
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
        }
    }
}
