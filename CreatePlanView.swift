//
//  CreatePlanView.swift
//  surge15
//

import SwiftUI
import SwiftData

struct CreatePlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Optional preset group (e.g. opened from PlanGroupDetailView)
    var presetGroup: PlanGroup? = nil

    // Plan identity
    @State private var planName: String = ""
    @State private var selectedGroup: PlanGroup? = nil
    @State private var gradientIndex: Int = 0

    // Draft items
    @State private var draftItems: [DraftItem] = []

    // Exercise picker state
    @State private var pickerType: WorkoutItemType = .run
    @State private var pickerMeasure: WorkoutMeasure = .meters
    @State private var pickerTarget: Double = 400

    @Query(sort: \PlanGroup.name) private var allGroups: [PlanGroup]

    struct DraftItem: Identifiable {
        let id = UUID()
        var workoutType: WorkoutItemType
        var measure: WorkoutMeasure
        var targetValue: Double
    }

    private let lapPresets: [Double]     = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20, 25, 50]
    private let meterPresets: [Double]   = [1, 5, 10, 20, 40, 50, 75, 100, 125, 150, 200, 250,
                                            300, 350, 400, 450, 500, 550, 600, 650, 700, 750,
                                            800, 850, 900, 950, 1000]
    private let repPresets: [Double]     = [5, 10, 15, 20, 25, 30, 40, 50, 60, 75, 100]
    private let minutePresets: [Double]  = [0.5, 1, 1.5, 2, 2.5, 3, 4, 5, 7, 10, 15, 20]

    private let typeColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var isValid: Bool {
        !planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draftItems.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Plan identity
                Section {
                    previewCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                    GradientPickerView(selectedIndex: $gradientIndex)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    TextField("Plan Name", text: $planName)
                        .textInputAutocapitalization(.words)
                        .font(.headline)

                    if !allGroups.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Group")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    // No group option
                                    Button {
                                        selectedGroup = nil
                                    } label: {
                                        Text("None")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(selectedGroup == nil ? Color.blue : Color(.secondarySystemFill), in: Capsule())
                                            .foregroundStyle(selectedGroup == nil ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)

                                    ForEach(allGroups) { grp in
                                        Button {
                                            selectedGroup = grp
                                        } label: {
                                            HStack(spacing: 5) {
                                                Circle()
                                                    .fill(planGradients[grp.cardGradientIndex % planGradients.count].linear)
                                                    .frame(width: 10, height: 10)
                                                Text(grp.name)
                                                    .font(.caption.weight(.semibold))
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(selectedGroup?.id == grp.id ? Color.blue : Color(.secondarySystemFill), in: Capsule())
                                            .foregroundStyle(selectedGroup?.id == grp.id ? .white : .primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.bottom, 2)
                            }
                        }
                    }
                } header: {
                    Text("Plan Details")
                }

                // MARK: Exercise picker
                Section {
                    typeChipRow
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

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
                } header: {
                    Text("Add Exercise")
                }

                // MARK: Add button
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

                // MARK: Draft items
                if !draftItems.isEmpty {
                    Section {
                        ForEach(draftItems) { item in
                            draftItemRow(item)
                        }
                        .onDelete { draftItems.remove(atOffsets: $0) }
                        .onMove  { draftItems.move(fromOffsets: $0, toOffset: $1) }
                    } header: {
                        Text("Plan · \(draftItems.count) exercise\(draftItems.count == 1 ? "" : "s")")
                    }
                }
            }
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
                if !draftItems.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                }
            }
            .onAppear {
                if selectedGroup == nil, let preset = presetGroup {
                    selectedGroup = preset
                }
            }
        }
    }

    // MARK: - Card preview

    private var previewCard: some View {
        ZStack(alignment: .bottomLeading) {
            planGradients[gradientIndex % planGradients.count].linear

            LinearGradient(
                colors: [.clear, .black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text(planName.isEmpty ? "Plan Name" : planName)
                    .font(.title2.bold())
                    .foregroundStyle(planName.isEmpty ? .white.opacity(0.4) : .white)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    ForEach(draftItems.prefix(5)) { item in
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.22))
                                .frame(width: 28, height: 28)
                            Image(systemName: item.workoutType.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    if draftItems.isEmpty {
                        Text("No exercises yet")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: gradientIndex)
    }

    // MARK: - Exercise type grid

    private var typeChipRow: some View {
        LazyVGrid(columns: typeColumns, spacing: 8) {
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
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(pickerType == type ? Color.blue : Color(.secondarySystemFill), in: Capsule())
                    .foregroundStyle(pickerType == type ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Draft item row

    private func draftItemRow(_ item: DraftItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.workoutType.systemImage)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.workoutType.displayName).font(.headline)
                Text(item.measure.formatted(item.targetValue))
                    .font(.caption).foregroundStyle(.secondary)
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
            case .minutes: return value < 1 ? "\(Int(value * 60))s" : "\(Int(value))min"
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

    private func save() {
        let name = planName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let plan = Plan(name: name)
        plan.group = selectedGroup
        plan.cardGradientIndex = gradientIndex
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
        // Also append to group's plans array so the relationship is live immediately
        selectedGroup?.plans.append(plan)
        dismiss()
    }
}

#Preview {
    CreatePlanView()
        .modelContainer(for: Plan.self, inMemory: true)
}
