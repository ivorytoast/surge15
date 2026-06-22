//
//  PlanDetailView.swift
//  surge15
//

import SwiftUI
import SwiftData

struct PlanDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.startPlan) private var startPlan
    @Bindable var plan: Plan
    @State private var showingDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Card preview — full width, live-updating
                PlanCardView(plan: plan, featured: true)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 20)

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
                    }

                    // Identity card
                    VStack(alignment: .leading, spacing: 0) {
                        detailSectionHeader("Identity")

                        VStack(spacing: 0) {
                            inlineField(label: "Name") {
                                TextField("Plan name", text: $plan.name)
                                    .textInputAutocapitalization(.words)
                                    .multilineTextAlignment(.trailing)
                            }

                            Divider().padding(.leading, 16)

                            inlineField(label: "Group") {
                                Text(plan.group?.name ?? "None")
                                    .foregroundStyle(.secondary)
                            }

                            Divider().padding(.leading, 16)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Color")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                GradientPickerView(selectedIndex: $plan.cardGradientIndex)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)

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

                    // Danger zone
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Plan", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
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
        .alert("Delete this plan?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelContext.delete(plan)
                dismiss()
            }
        } message: {
            Text("Surge sessions previously created from this plan will keep their data.")
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

    private func inlineField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            content()
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        PlanDetailView(plan: Plan(name: "HYROX Simulation"))
    }
    .modelContainer(for: Plan.self, inMemory: true)
}
