//
//  CreatePlanView.swift
//  surge15
//

import SwiftUI
import SwiftData

struct CreatePlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var presetGroup: PlanGroup? = nil
    var editingPlan: Plan? = nil

    @State private var planName: String = ""
    @State private var selectedGroup: PlanGroup? = nil
    @State private var gradientIndex: Int = Int.random(in: 0..<planGradients.count)
    @State private var draftItems: [DraftItem] = []
    @State private var showingDetails = false

    @State private var pickerType: WorkoutItemType = .run
    @State private var pickerMeasure: WorkoutMeasure = .meters
    @State private var pickerTarget: Double = 10
    @State private var pickerTargetSeconds: Double? = nil

    @Query(sort: \PlanGroup.name) private var allGroups: [PlanGroup]

    struct DraftItem: Identifiable {
        let id = UUID()
        var workoutType: WorkoutItemType
        var measure: WorkoutMeasure
        var targetValue: Double
        var targetSeconds: Double? = nil
    }

    @AppStorage(pacePresetsKey)     private var pacePresetsStorage     = JSONStringArray<Double>(defaultPacePresets)
    @AppStorage(durationPresetsKey) private var durationPresetsStorage = JSONStringArray<Double>(defaultDurationPresets)

    private var pacePresets:     [Double] { pacePresetsStorage.values.sorted() }
    private var durationPresets: [Double] { durationPresetsStorage.values.sorted() }
    private var targetPresets:   [Double] { pickerType == .run ? pacePresets : durationPresets }

    @AppStorage(lapPresetsKey)    private var lapPresetsStorage    = JSONStringArray<Double>(defaultLapPresets.map(Double.init))
    @AppStorage(meterPresetsKey)  private var meterPresetsStorage  = JSONStringArray<Double>(defaultMeterPresets)
    @AppStorage(repPresetsKey)    private var repPresetsStorage    = JSONStringArray<Double>(defaultRepPresets)
    @AppStorage(minutePresetsKey) private var minutePresetsStorage = JSONStringArray<Double>(defaultMinutePresets)

    private var lapPresets:    [Double] { lapPresetsStorage.values.sorted() }
    private var meterPresets:  [Double] { meterPresetsStorage.values.sorted() }
    private var repPresets:    [Double] { repPresetsStorage.values.sorted() }
    private var minutePresets: [Double] { minutePresetsStorage.values.sorted() }

    private let typeColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Exercise picker
                Section("Add Exercise") {
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

                    if pickerType != .rest {
                        targetPickerRow
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 0))
                    }
                }

                // MARK: Add button
                Section {
                    Button {
                        draftItems.append(DraftItem(
                            workoutType: pickerType,
                            measure: pickerMeasure,
                            targetValue: pickerTarget,
                            targetSeconds: pickerTargetSeconds
                        ))
                    } label: {
                        Label("Add to Plan", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                // MARK: Draft list
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
            .navigationTitle(editingPlan == nil ? "New Plan" : "Edit Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { showingDetails = true }
                        .disabled(draftItems.isEmpty)
                }
            }
            .sheet(isPresented: $showingDetails) {
                planDetailsSheet
            }
            .onAppear {
                if let plan = editingPlan {
                    planName = plan.name
                    selectedGroup = plan.group
                    gradientIndex = plan.cardGradientIndex
                    draftItems = plan.sortedItems.map {
                        DraftItem(workoutType: $0.workoutType, measure: $0.measure,
                                  targetValue: $0.targetValue, targetSeconds: $0.targetSeconds)
                    }
                } else if selectedGroup == nil, let preset = presetGroup {
                    selectedGroup = preset
                }
            }
            .onChange(of: pickerType) { _, _ in pickerTargetSeconds = nil }
        }
    }

    // MARK: - Plan Details sheet

    private var planDetailsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Plan Name", text: $planName)
                        .textInputAutocapitalization(.words)
                        .font(.headline)
                } header: {
                    Text("Plan Details")
                }

                if !allGroups.isEmpty {
                    Section("Group") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button {
                                    selectedGroup = nil
                                } label: {
                                    Text("None")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
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
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(selectedGroup?.id == grp.id ? Color.blue : Color(.secondarySystemFill), in: Capsule())
                                        .foregroundStyle(selectedGroup?.id == grp.id ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 2)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
            }
            .navigationTitle("Plan Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { showingDetails = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingPlan == nil ? "Create" : "Save") { save() }
                        .disabled(planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Target picker row

    private var targetPickerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pickerType == .run ? "Pace target (optional)" : "Time target (optional)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { pickerTargetSeconds = nil } label: {
                        Text("Off")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(pickerTargetSeconds == nil ? Color.blue : Color(.secondarySystemFill), in: Capsule())
                            .foregroundStyle(pickerTargetSeconds == nil ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    ForEach(targetPresets, id: \.self) { seconds in
                        Button { pickerTargetSeconds = seconds } label: {
                            Text(targetChipLabel(seconds))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(pickerTargetSeconds == seconds ? Color.blue : Color(.secondarySystemFill), in: Capsule())
                                .foregroundStyle(pickerTargetSeconds == seconds ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.12), value: pickerTargetSeconds == seconds)
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
                if let ts = item.targetSeconds {
                    Text(item.workoutType == .run
                         ? "Target: \(targetChipLabel(ts))/km"
                         : "Target: \(Formatters.duration(ts))")
                        .font(.caption2)
                        .foregroundStyle(.blue.opacity(0.8))
                }
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

    private func targetChipLabel(_ seconds: Double) -> String {
        if pickerType == .run {
            let total = Int(seconds.rounded())
            return String(format: "%d:%02d", total / 60, total % 60)
        } else {
            return Formatters.duration(seconds)
        }
    }

    private func defaultTarget(for measure: WorkoutMeasure, type: WorkoutItemType) -> Double {
        switch measure {
        case .meters, .yards: return 10
        case .laps:           return 2
        case .reps:           return 10
        case .minutes:        return 2
        }
    }

    private func save() {
        let name = planName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if let plan = editingPlan {
            plan.name = name
            plan.group = selectedGroup
            plan.cardGradientIndex = gradientIndex
            for item in plan.items { modelContext.delete(item) }
            for (i, draft) in draftItems.enumerated() {
                plan.items.append(PlanItem(
                    order: i, workoutType: draft.workoutType,
                    measure: draft.measure, targetValue: draft.targetValue,
                    targetSeconds: draft.targetSeconds
                ))
            }
        } else {
            let plan = Plan(name: name)
            plan.group = selectedGroup
            plan.cardGradientIndex = gradientIndex
            for (i, draft) in draftItems.enumerated() {
                plan.items.append(PlanItem(
                    order: i, workoutType: draft.workoutType,
                    measure: draft.measure, targetValue: draft.targetValue,
                    targetSeconds: draft.targetSeconds
                ))
            }
            modelContext.insert(plan)
            selectedGroup?.plans.append(plan)
        }
        dismiss()
    }
}

#Preview {
    CreatePlanView()
        .modelContainer(for: Plan.self, inMemory: true)
}
