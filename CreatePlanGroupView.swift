//
//  CreatePlanGroupView.swift
//  surge15
//

import SwiftUI
import SwiftData

struct CreatePlanGroupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var groupName: String = ""
    @State private var gradientIndex: Int = 0

    private var isValid: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    previewCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Name") {
                    TextField("Group Name", text: $groupName)
                        .textInputAutocapitalization(.words)
                        .font(.headline)
                }

                Section {
                    GradientPickerView(selectedIndex: $gradientIndex)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Color")
                } footer: {
                    Text("You can add plans to this group later.")
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private var previewCard: some View {
        ZStack(alignment: .bottomLeading) {
            planGradients[gradientIndex % planGradients.count].linear
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Image(systemName: "folder.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.75))
                Text(groupName.isEmpty ? "Group Name" : groupName)
                    .font(.title2.bold())
                    .foregroundStyle(groupName.isEmpty ? .white.opacity(0.4) : .white)
                    .lineLimit(1)
                Text("0 plans")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: gradientIndex)
    }

    private func save() {
        let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let group = PlanGroup(name: name)
        group.cardGradientIndex = gradientIndex
        modelContext.insert(group)
        dismiss()
    }
}

#Preview {
    CreatePlanGroupView()
        .modelContainer(for: PlanGroup.self, inMemory: true)
}
