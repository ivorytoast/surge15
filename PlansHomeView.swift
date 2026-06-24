//
//  PlansHomeView.swift
//  surge15
//

import SwiftUI
import SwiftData

// MARK: - Gradient Palette

struct PlanGradient {
    let name: String
    let start: Color
    let end: Color

    var linear: LinearGradient {
        LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

let planGradients: [PlanGradient] = [
    PlanGradient(name: "Ocean",    start: .blue,                                        end: Color(red: 0.5, green: 0.0, blue: 0.9)),
    PlanGradient(name: "Forest",   start: Color(red: 0.0,  green: 0.75, blue: 0.5),    end: Color(red: 0.0, green: 0.45, blue: 0.75)),
    PlanGradient(name: "Ember",    start: Color(red: 1.0,  green: 0.45, blue: 0.0),    end: Color(red: 0.9, green: 0.05, blue: 0.25)),
    PlanGradient(name: "Rose",     start: Color(red: 1.0,  green: 0.25, blue: 0.5),    end: Color(red: 0.55, green: 0.0, blue: 0.8)),
    PlanGradient(name: "Sunrise",  start: Color(red: 1.0,  green: 0.75, blue: 0.0),    end: Color(red: 1.0, green: 0.3,  blue: 0.0)),
    PlanGradient(name: "Sky",      start: Color(red: 0.0,  green: 0.8,  blue: 0.95),   end: Color(red: 0.0, green: 0.35, blue: 0.85)),
    PlanGradient(name: "Cherry",   start: Color(red: 0.9,  green: 0.1,  blue: 0.25),   end: Color(red: 0.55, green: 0.0, blue: 0.5)),
    PlanGradient(name: "Midnight", start: Color(red: 0.1,  green: 0.1,  blue: 0.45),   end: Color(red: 0.25, green: 0.0, blue: 0.25)),
    PlanGradient(name: "Lime",     start: Color(red: 0.15, green: 0.7,  blue: 0.25),   end: Color(red: 0.65, green: 0.9, blue: 0.1)),
    PlanGradient(name: "Neon",     start: Color(red: 0.5,  green: 0.0,  blue: 0.85),   end: Color(red: 1.0, green: 0.15, blue: 0.5)),
    PlanGradient(name: "Citrus",   start: Color(red: 1.0,  green: 0.45, blue: 0.15),   end: Color(red: 1.0, green: 0.85, blue: 0.05)),
    PlanGradient(name: "Galaxy",   start: Color(red: 0.1,  green: 0.15, blue: 0.6),    end: Color(red: 0.4, green: 0.0,  blue: 0.75)),
]

// MARK: - Plan Card (used inside group detail)

struct PlanCardView: View {
    let plan: Plan
    var featured: Bool = false

    private var gradient: PlanGradient {
        planGradients[plan.cardGradientIndex % planGradients.count]
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            gradient.linear
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text(plan.name)
                    .font(featured ? .title2.bold() : .headline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                HStack(spacing: 5) {
                    ForEach(plan.sortedItems.prefix(5)) { item in
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.22))
                                .frame(width: 28, height: 28)
                            Image(systemName: item.workoutType.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    if plan.items.count > 5 {
                        Text("+\(plan.items.count - 5)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.leading, 2)
                    }
                }
            }
            .padding(14)
        }
        .frame(width: featured ? nil : 130, height: featured ? 190 : 118)
        .frame(maxWidth: featured ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topTrailing) {
            if plan.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(10)
            }
        }
    }
}

// MARK: - Group Card (top row of home screen)

struct PlanGroupCardView: View {
    let group: PlanGroup

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            planGradients[group.cardGradientIndex % planGradients.count].linear
            LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    if group.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
                Text(group.name)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                Text(group.plans.isEmpty ? "Empty" : "\(group.plans.count) plan\(group.plans.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(12)
        }
        .frame(width: 130, height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Gradient Picker

struct GradientPickerView: View {
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(planGradients.indices, id: \.self) { idx in
                    ZStack {
                        Circle()
                            .fill(planGradients[idx].linear)
                            .frame(width: 44, height: 44)
                        if selectedIndex == idx {
                            Circle()
                                .strokeBorder(.white, lineWidth: 3)
                                .frame(width: 44, height: 44)
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                    }
                    .onTapGesture { selectedIndex = idx }
                    .animation(.easeInOut(duration: 0.15), value: selectedIndex)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Smart group navigation target

enum SmartGroupDestination: Hashable {
    case favoriteGroups
    case favoritePlans
}

// MARK: - Smart group card (for the "For You" row)

struct SmartGroupCardView: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: LinearGradient

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            gradient
            LinearGradient(colors: [.clear, .black.opacity(0.38)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Plans Home

struct PlansHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \PlanGroup.createdAt, order: .reverse) private var groups: [PlanGroup]
    @Query(sort: \Plan.createdAt, order: .reverse) private var allPlans: [Plan]

    @State private var showingCreateGroup = false
    @State private var showingCreatePlan  = false

    // Group rename/delete/recolor (triggered from long-press on group card)
    @State private var renamingGroup: PlanGroup? = nil
    @State private var groupRenameText = ""
    @State private var recoloringGroup: PlanGroup? = nil
    @State private var deletingGroup: PlanGroup? = nil

    // Plan rename/delete/move (triggered from long-press on plan row)
    @State private var renamingPlan: Plan? = nil
    @State private var planRenameText = ""
    @State private var movingPlan: Plan? = nil
    @State private var deletingPlan: Plan? = nil

    private var allPlansSorted: [Plan] {
        allPlans.sorted { $0.surgeSessions.count > $1.surgeSessions.count }
    }
    private var favoriteGroupCount: Int { groups.filter { $0.isFavorite }.count }
    private var favoritePlanCount: Int  { allPlans.filter { $0.isFavorite }.count }

    // MARK: - Adaptive palette
    private var isLight: Bool { colorScheme == .light }
    // #f5f8fd ↔ #070a18
    private var pageBackground: Color { isLight ? Color(red: 0.961, green: 0.973, blue: 0.992) : Color(red: 0.027, green: 0.039, blue: 0.094) }
    // white ↔ #0e1430
    private var rowBackground: Color { isLight ? .white : Color(red: 0.055, green: 0.078, blue: 0.188) }
    // #0f172a ↔ white
    private var headingColor: Color { isLight ? Color(red: 0.059, green: 0.090, blue: 0.165) : .white }
    // #9fb0d4 ↔ #c2cde4
    private var rowIconColor: Color { isLight ? Color(red: 0.624, green: 0.690, blue: 0.831) : Color(red: 0.761, green: 0.804, blue: 0.894) }
    // #c2cde4 ↔ #9fb0d4
    private var rowChevronColor: Color { isLight ? Color(red: 0.761, green: 0.804, blue: 0.894) : Color(red: 0.624, green: 0.690, blue: 0.831) }
    // #2563eb ↔ #60a5fa
    private var sectionLabelColor: Color { isLight ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color(red: 0.376, green: 0.647, blue: 0.980) }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty && allPlans.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            // Row 1: All groups
                            if !groups.isEmpty {
                                groupScrollRow(title: "Groups", groups: groups)
                            }

                            // Row 2: For You (always present, two fixed smart cards)
                            forYouRow

                            // Row 3: Ungrouped plans
                            if !allPlansSorted.isEmpty {
                                ungroupedSection
                            }
                        }
                        .padding(.vertical)
                    }
                    .background(pageBackground.ignoresSafeArea())
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingCreateGroup = true } label: {
                            Label("New Group", systemImage: "folder.badge.plus")
                        }
                        Button { showingCreatePlan = true } label: {
                            Label("New Plan", systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Plan.self) { plan in
                PlanDetailView(plan: plan)
            }
            .navigationDestination(for: PlanGroup.self) { group in
                PlanGroupDetailView(group: group)
            }
            .navigationDestination(for: SmartGroupDestination.self) { dest in
                switch dest {
                case .favoriteGroups: FavoriteGroupsView()
                case .favoritePlans:  FavoritePlansView()
                }
            }
            .sheet(isPresented: $showingCreateGroup) {
                CreatePlanGroupView()
            }
            .sheet(isPresented: $showingCreatePlan) {
                CreatePlanView()
            }
            .sheet(item: $movingPlan) { plan in
                MovePlanToGroupSheet(plan: plan, groups: groups)
            }
            .sheet(item: $recoloringGroup) { group in
                GroupColorPickerSheet(group: group)
            }
            .alert("Rename Group", isPresented: Binding(
                get: { renamingGroup != nil },
                set: { if !$0 { renamingGroup = nil } }
            )) {
                TextField("Group name", text: $groupRenameText)
                Button("Save") {
                    let t = groupRenameText.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { renamingGroup?.name = t }
                    renamingGroup = nil
                }
                Button("Cancel", role: .cancel) { renamingGroup = nil }
            }
            .alert("Rename Plan", isPresented: Binding(
                get: { renamingPlan != nil },
                set: { if !$0 { renamingPlan = nil } }
            )) {
                TextField("Plan name", text: $planRenameText)
                Button("Save") {
                    let t = planRenameText.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { renamingPlan?.name = t }
                    renamingPlan = nil
                }
                Button("Cancel", role: .cancel) { renamingPlan = nil }
            }
            .alert("Delete Group", isPresented: Binding(
                get: { deletingGroup != nil },
                set: { if !$0 { deletingGroup = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let group = deletingGroup { modelContext.delete(group) }
                    deletingGroup = nil
                }
                Button("Cancel", role: .cancel) { deletingGroup = nil }
            } message: {
                Text("Are you sure you want to delete \"\(deletingGroup?.name ?? "")\"? This cannot be undone.")
            }
            .alert("Delete Plan", isPresented: Binding(
                get: { deletingPlan != nil },
                set: { if !$0 { deletingPlan = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let plan = deletingPlan { modelContext.delete(plan) }
                    deletingPlan = nil
                }
                Button("Cancel", role: .cancel) { deletingPlan = nil }
            } message: {
                Text("Are you sure you want to delete \"\(deletingPlan?.name ?? "")\"? This cannot be undone.")
            }
        }
    }

    // MARK: - For You row (two fixed smart cards, always present)

    private var forYouRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            planSectionHeader("For You")
                .padding(.horizontal)

            HStack(spacing: 12) {
                NavigationLink(value: SmartGroupDestination.favoriteGroups) {
                    SmartGroupCardView(
                        title: "Favorite Groups",
                        subtitle: favoriteGroupCount == 0 ? "None yet" : "\(favoriteGroupCount) group\(favoriteGroupCount == 1 ? "" : "s")",
                        icon: "heart.fill",
                        // #1e3a8a → #2563eb  Navy → Primary Blue
                        gradient: LinearGradient(
                            colors: [Color(red: 0.118, green: 0.227, blue: 0.541), Color(red: 0.145, green: 0.388, blue: 0.922)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: SmartGroupDestination.favoritePlans) {
                    SmartGroupCardView(
                        title: "Favorite Plans",
                        subtitle: favoritePlanCount == 0 ? "None yet" : "\(favoritePlanCount) plan\(favoritePlanCount == 1 ? "" : "s")",
                        icon: "star.fill",
                        // #15235a → #60a5fa  Mid Navy → Light Blue
                        gradient: LinearGradient(
                            colors: [Color(red: 0.082, green: 0.137, blue: 0.353), Color(red: 0.376, green: 0.647, blue: 0.980)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Horizontal group card row

    private func groupScrollRow(title: String, groups: [PlanGroup]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            planSectionHeader(title)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(groups) { group in
                        NavigationLink(value: group) {
                            PlanGroupCardView(group: group)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                groupRenameText = group.name
                                renamingGroup = group
                            } label: {
                                Label("Rename Group", systemImage: "pencil")
                            }
                            Button {
                                recoloringGroup = group
                            } label: {
                                Label("Change Color", systemImage: "paintpalette")
                            }
                            Button(role: .destructive) {
                                deletingGroup = group
                            } label: {
                                Label("Delete Group", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Ungrouped plans (vertical list)

    private var ungroupedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            planSectionHeader("All Plans")
                .padding(.horizontal)
            VStack(spacing: 0) {
                ForEach(Array(allPlansSorted.enumerated()), id: \.element.id) { idx, plan in
                    NavigationLink(value: plan) {
                        ungroupedPlanRow(plan, isLast: idx == allPlansSorted.count - 1)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            planRenameText = plan.name
                            renamingPlan = plan
                        } label: {
                            Label("Rename Plan", systemImage: "pencil")
                        }
                        if !groups.isEmpty {
                            Button { movingPlan = plan } label: {
                                Label("Add to Group", systemImage: "folder")
                            }
                        }
                        Button(role: .destructive) {
                            deletingPlan = plan
                        } label: {
                            Label("Delete Plan", systemImage: "trash")
                        }
                    }
                }
            }
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 24)
    }

    private func ungroupedPlanRow(_ plan: Plan, isLast: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isLight ? Color(red: 0.878, green: 0.922, blue: 0.996) : Color(red: 0.118, green: 0.227, blue: 0.541))
                    .frame(width: 36, height: 36)
                Text("\(plan.surgeSessions.count)")
                    .font(.headline.bold())
                    .foregroundStyle(sectionLabelColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(.headline)
                    .foregroundStyle(headingColor)
                Text("\(plan.items.count) exercise\(plan.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(rowIconColor)
            }

            Spacer()

            if plan.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.922, green: 0.302, blue: 0.400))
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(rowChevronColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Color(isLight ? Color(red: 0.749, green: 0.859, blue: 0.996) : Color(red: 0.118, green: 0.227, blue: 0.541))
                    .frame(height: 0.5)
                    .padding(.leading, 64)
            }
        }
    }

    private func planSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(sectionLabelColor)
            .textCase(.uppercase)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Plans Yet", systemImage: "list.clipboard")
        } description: {
            Text("Tap + to create a group or build a standalone plan.")
        }
    }
}

// MARK: - Favorite Groups View

struct FavoriteGroupsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlanGroup.createdAt, order: .reverse) private var allGroups: [PlanGroup]

    @State private var renamingGroup: PlanGroup? = nil
    @State private var groupRenameText = ""
    @State private var recoloringGroup: PlanGroup? = nil
    @State private var deletingGroup: PlanGroup? = nil

    private var favoriteGroups: [PlanGroup] { allGroups.filter { $0.isFavorite } }

    private var isLight: Bool { colorScheme == .light }
    private var pageBackground: Color { isLight ? Color(red: 0.961, green: 0.973, blue: 0.992) : Color(red: 0.027, green: 0.039, blue: 0.094) }
    private var rowBackground: Color { isLight ? .white : Color(red: 0.055, green: 0.078, blue: 0.188) }
    private var headingColor: Color { isLight ? Color(red: 0.059, green: 0.090, blue: 0.165) : .white }
    private var rowIconColor: Color { isLight ? Color(red: 0.624, green: 0.690, blue: 0.831) : Color(red: 0.761, green: 0.804, blue: 0.894) }
    private var rowChevronColor: Color { isLight ? Color(red: 0.761, green: 0.804, blue: 0.894) : Color(red: 0.624, green: 0.690, blue: 0.831) }
    private var sectionLabelColor: Color { isLight ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color(red: 0.376, green: 0.647, blue: 0.980) }

    var body: some View {
        Group {
            if favoriteGroups.isEmpty {
                ContentUnavailableView {
                    Label("No Favorite Groups", systemImage: "heart")
                } description: {
                    Text("Tap the heart on any group to add it here.")
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(favoriteGroups.enumerated()), id: \.element.id) { idx, group in
                            NavigationLink(value: group) {
                                groupRow(group, isLast: idx == favoriteGroups.count - 1)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    groupRenameText = group.name
                                    renamingGroup = group
                                } label: {
                                    Label("Rename Group", systemImage: "pencil")
                                }
                                Button {
                                    recoloringGroup = group
                                } label: {
                                    Label("Change Color", systemImage: "paintpalette")
                                }
                                Button(role: .destructive) {
                                    deletingGroup = group
                                } label: {
                                    Label("Delete Group", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .background(rowBackground, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .background(pageBackground.ignoresSafeArea())
            }
        }
        .navigationTitle("Favorite Groups")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PlanGroup.self) { group in
            PlanGroupDetailView(group: group)
        }
        .sheet(item: $recoloringGroup) { group in
            GroupColorPickerSheet(group: group)
        }
        .alert("Rename Group", isPresented: Binding(
            get: { renamingGroup != nil },
            set: { if !$0 { renamingGroup = nil } }
        )) {
            TextField("Group name", text: $groupRenameText)
            Button("Save") {
                let t = groupRenameText.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { renamingGroup?.name = t }
                renamingGroup = nil
            }
            Button("Cancel", role: .cancel) { renamingGroup = nil }
        }
        .alert("Delete Group", isPresented: Binding(
            get: { deletingGroup != nil },
            set: { if !$0 { deletingGroup = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let group = deletingGroup { modelContext.delete(group) }
                deletingGroup = nil
            }
            Button("Cancel", role: .cancel) { deletingGroup = nil }
        } message: {
            Text("Are you sure you want to delete \"\(deletingGroup?.name ?? "")\"? This cannot be undone.")
        }
    }

    private func groupRow(_ group: PlanGroup, isLast: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(planGradients[group.cardGradientIndex % planGradients.count].linear)
                    .frame(width: 36, height: 36)
                Text("\(group.plans.count)")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(headingColor)
                Text("\(group.plans.count) plan\(group.plans.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(rowIconColor)
            }

            Spacer()

            Image(systemName: "heart.fill")
                .font(.caption)
                .foregroundStyle(Color(red: 0.922, green: 0.302, blue: 0.400))
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(rowChevronColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Color(isLight ? Color(red: 0.749, green: 0.859, blue: 0.996) : Color(red: 0.118, green: 0.227, blue: 0.541))
                    .frame(height: 0.5)
                    .padding(.leading, 64)
            }
        }
    }
}

// MARK: - Favorite Plans View

struct FavoritePlansView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Plan.createdAt, order: .reverse) private var allPlans: [Plan]
    @Query(sort: \PlanGroup.createdAt, order: .reverse) private var groups: [PlanGroup]

    @State private var renamingPlan: Plan? = nil
    @State private var planRenameText = ""
    @State private var movingPlan: Plan? = nil
    @State private var deletingPlan: Plan? = nil

    private var favoritePlans: [Plan] {
        allPlans.filter { $0.isFavorite }
            .sorted { $0.surgeSessions.count > $1.surgeSessions.count }
    }

    private var isLight: Bool { colorScheme == .light }
    private var pageBackground: Color { isLight ? Color(red: 0.961, green: 0.973, blue: 0.992) : Color(red: 0.027, green: 0.039, blue: 0.094) }
    private var rowBackground: Color { isLight ? .white : Color(red: 0.055, green: 0.078, blue: 0.188) }
    private var headingColor: Color { isLight ? Color(red: 0.059, green: 0.090, blue: 0.165) : .white }
    private var rowIconColor: Color { isLight ? Color(red: 0.624, green: 0.690, blue: 0.831) : Color(red: 0.761, green: 0.804, blue: 0.894) }
    private var rowChevronColor: Color { isLight ? Color(red: 0.761, green: 0.804, blue: 0.894) : Color(red: 0.624, green: 0.690, blue: 0.831) }
    private var sectionLabelColor: Color { isLight ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color(red: 0.376, green: 0.647, blue: 0.980) }

    var body: some View {
        Group {
            if favoritePlans.isEmpty {
                ContentUnavailableView {
                    Label("No Favorite Plans", systemImage: "star")
                } description: {
                    Text("Tap the heart on any plan to add it here.")
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(favoritePlans.enumerated()), id: \.element.id) { idx, plan in
                            NavigationLink(value: plan) {
                                planRow(plan, isLast: idx == favoritePlans.count - 1)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    planRenameText = plan.name
                                    renamingPlan = plan
                                } label: {
                                    Label("Rename Plan", systemImage: "pencil")
                                }
                                if !groups.isEmpty {
                                    Button { movingPlan = plan } label: {
                                        Label("Move to Group", systemImage: "folder")
                                    }
                                }
                                Button(role: .destructive) {
                                    deletingPlan = plan
                                } label: {
                                    Label("Delete Plan", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .background(rowBackground, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .background(pageBackground.ignoresSafeArea())
            }
        }
        .navigationTitle("Favorite Plans")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Plan.self) { plan in
            PlanDetailView(plan: plan)
        }
        .sheet(item: $movingPlan) { plan in
            MovePlanToGroupSheet(plan: plan, groups: groups)
        }
        .alert("Rename Plan", isPresented: Binding(
            get: { renamingPlan != nil },
            set: { if !$0 { renamingPlan = nil } }
        )) {
            TextField("Plan name", text: $planRenameText)
            Button("Save") {
                let t = planRenameText.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { renamingPlan?.name = t }
                renamingPlan = nil
            }
            Button("Cancel", role: .cancel) { renamingPlan = nil }
        }
        .alert("Delete Plan", isPresented: Binding(
            get: { deletingPlan != nil },
            set: { if !$0 { deletingPlan = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let plan = deletingPlan { modelContext.delete(plan) }
                deletingPlan = nil
            }
            Button("Cancel", role: .cancel) { deletingPlan = nil }
        } message: {
            Text("Are you sure you want to delete \"\(deletingPlan?.name ?? "")\"? This cannot be undone.")
        }
    }

    private func planRow(_ plan: Plan, isLast: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isLight ? Color(red: 0.878, green: 0.922, blue: 0.996) : Color(red: 0.118, green: 0.227, blue: 0.541))
                    .frame(width: 36, height: 36)
                Text("\(plan.surgeSessions.count)")
                    .font(.headline.bold())
                    .foregroundStyle(sectionLabelColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(.headline)
                    .foregroundStyle(headingColor)
                Text("\(plan.items.count) exercise\(plan.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(rowIconColor)
            }

            Spacer()

            Image(systemName: "heart.fill")
                .font(.caption)
                .foregroundStyle(Color(red: 0.922, green: 0.302, blue: 0.400))
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(rowChevronColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Color(isLight ? Color(red: 0.749, green: 0.859, blue: 0.996) : Color(red: 0.118, green: 0.227, blue: 0.541))
                    .frame(height: 0.5)
                    .padding(.leading, 64)
            }
        }
    }
}

// MARK: - Group Color Picker Sheet

struct GroupColorPickerSheet: View {
    @Bindable var group: PlanGroup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                PlanGroupCardView(group: group)
                    .frame(maxWidth: 200)
                    .padding(.top, 8)

                GradientPickerView(selectedIndex: $group.cardGradientIndex)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Change Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    PlansHomeView()
        .modelContainer(for: [Plan.self, PlanGroup.self, PlanItem.self], inMemory: true)
}
