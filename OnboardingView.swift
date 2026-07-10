//
//  OnboardingView.swift
//  surge15
//

import SwiftUI

// MARK: - Intro screen (phase 0)

struct OnboardingIntroView: View {
    @AppStorage("onboardingPhase") private var onboardingPhase: Int = 0
    @State private var page: Int = 0

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(onboardingHex: "070a18"), location: 0),
                    .init(color: Color(onboardingHex: "0e1430"), location: 0.5),
                    .init(color: Color(onboardingHex: "15235a"), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ConceptStepView().tag(0)
                    BuildingBlocksView().tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { i in
                        Circle()
                            .fill(page == i ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)
                            .animation(.easeOut(duration: 0.2), value: page)
                    }
                }
                .padding(.bottom, 14)

                Button {
                    if page == 0 {
                        withAnimation(.easeOut(duration: 0.3)) { page = 1 }
                    } else {
                        withAnimation(.easeOut(duration: 0.25)) { onboardingPhase = 1 }
                    }
                } label: {
                    Text(page == 0 ? "Next" : "Get Started")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color(onboardingHex: "2563eb"))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .animation(.easeOut(duration: 0.2), value: page)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - Concept step

private struct ConceptStepView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "bolt.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color(onboardingHex: "60a5fa"))
                .shadow(color: Color(onboardingHex: "2563eb").opacity(0.7), radius: 20)

            VStack(spacing: 20) {
                Text("Train Where\nYou Are")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Functional training and running rarely share the same space. Pick your anchor point — a park, a sports field, a stretch of beach — and everything starts from there.")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(onboardingHex: "c2cde4"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)

                Text("Anywhere. Your Track. Surge.")
                    .font(.body)
                    .italic()
                    .foregroundStyle(Color(onboardingHex: "60a5fa").opacity(0.85))
            }
            .padding(.horizontal, 28)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Building blocks page (page 2 of intro)

private struct BuildingBlocksView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Text("Two Building Blocks")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                VStack(spacing: 24) {
                    conceptRow(
                        number: 1,
                        title: "Routes",
                        body: "Record the shortest loop near your spot once. Surge takes care of the rest."
                    )
                    conceptRow(
                        number: 2,
                        title: "Plans",
                        body: "Want to combine functional workouts with your routes? Plans solve this."
                    )
                }
            }
            .padding(.horizontal, 28)

            Spacer()
            Spacer()
        }
    }

    private func conceptRow(number: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(onboardingHex: "2563eb"), Color(onboardingHex: "60a5fa")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Text("\(number)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(body)
                    .font(.body)
                    .foregroundStyle(Color(onboardingHex: "c2cde4"))
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Reusable callout bubble (phases 1 and 2)

struct OnboardingCallout: View {
    let title: String
    let message: String
    var buttonTitle: String = "Got It"
    var gotItAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text(message)
                .font(.body)
                .foregroundStyle(Color(onboardingHex: "c2cde4"))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(5)

            if let action = gotItAction {
                Button(buttonTitle) { action() }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(onboardingHex: "2563eb"), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 2)
            }
        }
        .padding(20)
        .background(Color(onboardingHex: "1e3a8a"), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color(onboardingHex: "60a5fa").opacity(0.6), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
    }
}

// MARK: - Color helper

extension Color {
    init(onboardingHex hex: String) {
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
