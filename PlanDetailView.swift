//
//  PlanDetailView.swift
//  surge15
//

import SwiftUI
import SwiftData

struct PlanDetailView: View {
    @Environment(\.startPlan) private var startPlan
    @Bindable var plan: Plan

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                    // Start CTA
                    if let startPlan, !plan.items.isEmpty {
                        Button { startPlan(plan) } label: {
                            Label("Start This Plan", systemImage: "bolt.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        .padding(.top, 16)
                    }

                    // Exercises card
                    VStack(alignment: .leading, spacing: 0) {
                        detailSectionHeader("Exercises  ·  \(plan.items.count)")

                        if plan.sortedItems.isEmpty {
                            Text("No exercises in this plan.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(plan.sortedItems.enumerated()), id: \.element.id) { idx, item in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.blue.opacity(0.12))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: item.workoutType.systemImage)
                                                .font(.system(size: 15))
                                                .foregroundStyle(.blue)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.workoutType.displayName)
                                                .font(.headline)
                                            Text(item.displayTarget)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Text("\(idx + 1)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)

                                    if idx < plan.sortedItems.count - 1 {
                                        Divider().padding(.leading, 64)
                                    }
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal)

                    Spacer().frame(height: 16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    plan.isFavorite.toggle()
                } label: {
                    Image(systemName: plan.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(plan.isFavorite ? .red : .secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func detailSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 4)
            .padding(.bottom, 6)
    }

}

#Preview {
    NavigationStack {
        PlanDetailView(plan: Plan(name: "HYROX Simulation"))
    }
    .modelContainer(for: Plan.self, inMemory: true)
}
