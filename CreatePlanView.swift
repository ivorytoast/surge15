//
//  CreatePlanView.swift
//  surge15
//
//  Exercise picker + growing list in one screen. No separate sheet needed.
//

import SwiftUI
import SwiftData

struct CreatePlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draftItems: [DraftItem] = []
    @State private var showingNamePrompt = false
    @State private var pendingName = ""

    // Inline picker state
    @State private var pickerType: WorkoutItemType = .run
    @State private var pickerMeasure: WorkoutMeasure = .meters
    @State private var pickerTarget: Double = 400

    struct DraftItem: Identifiable {
        let id = UUID()
        var workoutType: WorkoutItemType
        var measure: WorkoutMeasure
        var targetValue: Double
    }

    private let lapPresets: [Double]     = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20, 25, 50]
    private let meterPresets: [Double]  = [1, 5, 10, 20, 40, 50, 75, 100, 125, 150, 200, 250,
                                           300, 350, 400, 450, 500, 550, 600, 650, 700, 750,
                                           800, 850, 900, 950, 1000]
    private let repPresets: [Double]    = [5, 10, 15, 20, 25, 30, 40, 50, 60, 75, 100]
    private let minutePresets: [Double] = [0.5, 1, 1.5, 2, 2.5, 3, 4, 5, 7, 10, 15, 20]

    var body: some View {
        NavigationStack {
            Form {
                pickerSection
                addButtonSection
                if !draftItems.isEmpty {
                    planItemsSection
                }
            }
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        pendingName = ""
                        showingNamePrompt = true
                    }
                    .disabled(!isValid)
                }
                if !draftItems.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                }
            }
            .alert("Name Your Plan", isPresented: $showingNamePrompt) {
                TextField("e.g. HYROX Simulation", text: $pendingName)
                    .textInputAutocapitalization(.words)
                Button("Save") { save() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Give your plan a name to save it.")
            }
        }
    }

    // MARK: - Picker section

    private var pickerSection: some View {
        Section {
            typeChipRow
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))

            if pickerType.availableMeasures.count > 1 {
                Picker("Measure", selection: $pickerMeasure) {
                    ForEach(pickerType.availableMeasures, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: pickerMeasure) { _, newMeasure in
                    pickerTarget = defaultTarget(for: newMeasure, type: pickerType)
                }
            }

            chipScrollRow
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))
        }
    }

    private var typeChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WorkoutItemType.allCases) { type in
                    Button {
                        pickerType = type
                        if !type.availableMeasures.contains(pickerMeasure) {
                            pickerMeasure = type.availableMeasures[0]
                        }
                        pickerTarget = defaultTarget(for: pickerMeasure, type: type)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: type.systemImage)
                                .font(.caption.weight(.semibold))
                            Text(type.shortName)
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(pickerType == type ? Color.blue : Color(.secondarySystemFill), in: Capsule())
                        .foregroundStyle(pickerType == type ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .padding(.leading, 2)
        }
        .mask(
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 40)
            }
        )
    }

    // MARK: - Add button

    private var addButtonSection: some View {
        Section {
            Button {
                draftItems.append(DraftItem(
                    workoutType: pickerType,
                    measure: pickerMeasure,
                    targetValue: pickerTarget
                ))
            } label: {
                Label("Add to Plan", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Plan items list

    private var planItemsSection: some View {
        Section {
            ForEach(draftItems) { item in
                draftItemRow(item)
            }
            .onDelete { draftItems.remove(atOffsets: $0) }
            .onMove { draftItems.move(fromOffsets: $0, toOffset: $1) }
        } header: {
            Text("Plan · \(draftItems.count) exercise\(draftItems.count == 1 ? "" : "s")")
        }
    }

    private func draftItemRow(_ item: DraftItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.workoutType.systemImage)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.workoutType.displayName)
                    .font(.headline)
                Text(item.measure.formatted(item.targetValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Chip scroll

    private var chipScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(currentPresets, id: \.self) { preset in
                    chip(preset)
                }
            }
            .padding(.vertical, 4)
            .padding(.leading, 2)
        }
        .mask(
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 40)
            }
        )
    }

    private func chip(_ value: Double) -> some View {
        let selected = value == pickerTarget
        let label: String = {
            switch pickerMeasure {
            case .meters:  return value >= 1000 ? String(format: "%.1fk", value / 1000) : "\(Int(value))m"
            case .yards:   return "\(Int(value))yd"
            case .laps:    return "\(Int(value))"
            case .reps:    return "\(Int(value))"
            case .minutes: return value < 1 ? "\(Int(value * 60))s" : "\(Int(value))m"
            }
        }()
        return Button { pickerTarget = value } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Color.blue : Color(.secondarySystemFill), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var currentPresets: [Double] {
        switch pickerMeasure {
        case .laps:           return lapPresets
        case .meters, .yards: return meterPresets
        case .reps:           return repPresets
        case .minutes:        return minutePresets
        }
    }

    // MARK: - Helpers

    private func defaultTarget(for measure: WorkoutMeasure, type: WorkoutItemType) -> Double {
        switch measure {
        case .meters, .yards: return (type == .run || type == .row) ? 400 : 24
        case .laps:           return 1
        case .reps:           return 10
        case .minutes:        return 2
        }
    }

    private var isValid: Bool { !draftItems.isEmpty }

    private func save() {
        let trimmed = pendingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let plan = Plan(name: trimmed)
        for (i, draft) in draftItems.enumerated() {
            let item = PlanItem(
                order: i,
                workoutType: draft.workoutType,
                measure: draft.measure,
                targetValue: draft.targetValue
            )
            plan.items.append(item)
        }
        modelContext.insert(plan)
        dismiss()
    }
}

#Preview {
    CreatePlanView()
        .modelContainer(for: Plan.self, inMemory: true)
}
