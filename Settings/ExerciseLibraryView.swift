//
//  ExerciseLibraryView.swift
//  surge15
//
//  Settings page to manage the exercise library: hide/show built-ins,
//  add/edit/delete custom exercises, and pick SF Symbol icons.
//

import SwiftUI
import SwiftData

// MARK: - Library

struct ExerciseLibraryView: View {
    @Query(sort: \CustomExercise.sortOrder) private var customExercises: [CustomExercise]
    @Environment(\.modelContext) private var modelContext
    @AppStorage(hiddenBuiltinExercisesKey) private var hiddenBuiltinsRaw: String = ""

    @State private var showingAddSheet = false
    @State private var editingExercise: CustomExercise? = nil

    private var hiddenBuiltins: Set<String> {
        Set(hiddenBuiltinsRaw.split(separator: ",").map(String.init))
    }

    // Built-ins shown in the library (exclude .run since it's GPS-only)
    private let manageableBuiltins: [WorkoutItemType] = [
        .lunge, .burpeeBroadJump, .row, .wallBall, .rest
    ]

    var body: some View {
        List {
            Section {
                ForEach(manageableBuiltins) { type in
                    HStack(spacing: 14) {
                        Image(systemName: type.systemImage)
                            .frame(width: 28)
                            .foregroundStyle(.secondary)
                        Text(type.displayName)
                            .foregroundStyle(hiddenBuiltins.contains(type.rawValue) ? .secondary : .primary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !hiddenBuiltins.contains(type.rawValue) },
                            set: { visible in
                                if visible { removeFromHidden(type.rawValue) }
                                else { addToHidden(type.rawValue) }
                            }
                        ))
                        .labelsHidden()
                    }
                }
            } header: {
                Text("Built-in Exercises")
            } footer: {
                Text("Toggle to show or hide built-in exercises in the exercise picker.")
            }

            Section {
                ForEach(customExercises) { exercise in
                    Button { editingExercise = exercise } label: {
                        HStack(spacing: 14) {
                            Image(systemName: exercise.iconName)
                                .frame(width: 28)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .foregroundStyle(.primary)
                                Text(exercise.measures.map(\.displayName).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                }
                .onDelete { indexSet in
                    indexSet.forEach { modelContext.delete(customExercises[$0]) }
                }

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
            } header: {
                Text("My Exercises")
            } footer: {
                Text("Custom exercises appear in the exercise picker. Names are limited to 20 characters.")
            }
        }
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddSheet) {
            ExerciseEditSheet(exercise: nil) { name, icon, measures in
                let order = customExercises.count
                let ex = CustomExercise(name: name, iconName: icon, measures: measures, sortOrder: order)
                modelContext.insert(ex)
            }
        }
        .sheet(item: $editingExercise) { exercise in
            ExerciseEditSheet(exercise: exercise) { name, icon, measures in
                exercise.name = name
                exercise.iconName = icon
                exercise.measures = measures
            }
        }
    }

    private func addToHidden(_ rawValue: String) {
        var hidden = hiddenBuiltins
        hidden.insert(rawValue)
        hiddenBuiltinsRaw = hidden.joined(separator: ",")
    }

    private func removeFromHidden(_ rawValue: String) {
        var hidden = hiddenBuiltins
        hidden.remove(rawValue)
        hiddenBuiltinsRaw = hidden.joined(separator: ",")
    }
}

// MARK: - Edit / Create sheet

struct ExerciseEditSheet: View {
    let exercise: CustomExercise?
    let onSave: (String, String, [WorkoutMeasure]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var iconName: String
    @State private var selectedMeasures: Set<WorkoutMeasure>
    @State private var showingIconPicker = false

    private let maxNameLength = 20
    private let availableMeasures: [WorkoutMeasure] = [.reps, .meters, .yards, .minutes]

    init(exercise: CustomExercise?, onSave: @escaping (String, String, [WorkoutMeasure]) -> Void) {
        self.exercise = exercise
        self.onSave = onSave
        _name = State(initialValue: exercise?.name ?? "")
        _iconName = State(initialValue: exercise?.iconName ?? "figure.mixed.cardio")
        _selectedMeasures = State(initialValue: Set(exercise?.measures ?? [.reps]))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var orderedMeasures: [WorkoutMeasure] {
        availableMeasures.filter { selectedMeasures.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Button { showingIconPicker = true } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 56, height: 56)
                                Image(systemName: iconName)
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Exercise Name", text: $name)
                                .font(.headline)
                                .onChange(of: name) { _, new in
                                    if new.count > maxNameLength {
                                        name = String(new.prefix(maxNameLength))
                                    }
                                }
                            Text("\(name.count)/\(maxNameLength)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Name & Icon")
                } footer: {
                    Text("Tap the icon to choose a different one.")
                }

                Section {
                    ForEach(availableMeasures, id: \.self) { m in
                        Button {
                            if selectedMeasures.contains(m) {
                                if selectedMeasures.count > 1 { selectedMeasures.remove(m) }
                            } else {
                                selectedMeasures.insert(m)
                            }
                        } label: {
                            HStack {
                                Text(m.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedMeasures.contains(m) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Measurement")
                } footer: {
                    Text("Select all that apply. Users can switch between them when recording.")
                }
            }
            .navigationTitle(exercise == nil ? "New Exercise" : "Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedName, iconName, orderedMeasures)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || selectedMeasures.isEmpty)
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerSheet(selectedIcon: $iconName)
            }
        }
    }
}

// MARK: - Icon picker

struct IconPickerSheet: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss

    private let icons: [String] = [
        "figure.strengthtraining.functional",
        "figure.strengthtraining.traditional",
        "figure.mixed.cardio",
        "figure.gymnastics",
        "figure.jumprope",
        "figure.cooldown",
        "figure.yoga",
        "figure.pilates",
        "figure.boxing",
        "figure.martial.arts",
        "figure.handball",
        "figure.volleyball",
        "figure.core.training",
        "figure.highintensity.intervaltraining",
        "figure.mind.and.body",
        "figure.roll",
        "figure.outdoor.cycle",
        "figure.indoor.cycle",
        "figure.swimming",
        "figure.water.fitness",
        "figure.hiking",
        "figure.walk",
        "figure.run",
        "figure.surfing",
        "figure.skiing.downhill",
        "figure.dance",
        "dumbbell.fill",
        "oar.2.crossed",
        "bolt.heart.fill",
        "heart.circle.fill",
        "flame.fill",
        "star.circle.fill",
        "trophy.fill",
        "arrow.up.circle.fill",
        "hand.raised.fill",
        "person.fill"
    ]

    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(icons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                            dismiss()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(selectedIcon == icon ? Color.blue : Color(.secondarySystemFill))
                                    .aspectRatio(1, contentMode: .fit)
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundStyle(selectedIcon == icon ? .white : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    NavigationStack {
        ExerciseLibraryView()
    }
    .modelContainer(for: CustomExercise.self, inMemory: true)
}
