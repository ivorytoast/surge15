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
        .frame(width: featured ? nil : 170, height: featured ? 190 : 120)
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
        .frame(width: 130, height: 130)
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
        .frame(height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Plans Home

struct PlansHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlanGroup.createdAt, order: .reverse) private var groups: [PlanGroup]
    @Query(sort: \Plan.createdAt, order: .reverse) private var allPlans: [Plan]

    @State private var showingCreateGroup = false
    @State private var showingCreatePlan  = false

    private var ungroupedPlans: [Plan] { allPlans.filter { $0.group == nil } }
    private var favoriteGroupCount: Int { groups.filter { $0.isFavorite }.count }
    private var favoritePlanCount: Int  { allPlans.filter { $0.isFavorite }.count }

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
                            if !ungroupedPlans.isEmpty {
                                ungroupedSection
                            }
                        }
                        .padding(.vertical)
                    }
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
        }
    }

    // MARK: - For You row (two fixed smart cards, always present)

    private var forYouRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("For You")
                .font(.title3.bold())
                .padding(.horizontal)

            HStack(spacing: 12) {
                NavigationLink(value: SmartGroupDestination.favoriteGroups) {
                    SmartGroupCardView(
                        title: "Favorite Groups",
                        subtitle: favoriteGroupCount == 0 ? "None yet" : "\(favoriteGroupCount) group\(favoriteGroupCount == 1 ? "" : "s")",
                        icon: "heart.fill",
                        gradient: LinearGradient(
                            colors: [Color(red: 1.0, green: 0.25, blue: 0.4), Color(red: 0.8, green: 0.0, blue: 0.5)],
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
                        gradient: LinearGradient(
                            colors: [Color(red: 1.0, green: 0.6, blue: 0.0), Color(red: 0.9, green: 0.25, blue: 0.0)],
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

    private func groupScrollRow(title: String, icon: String? = nil, iconColor: Color = .primary, groups: [PlanGroup]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(iconColor)
                }
                Text(title)
                    .font(.title3.bold())
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(groups) { group in
                        NavigationLink(value: group) {
                            PlanGroupCardView(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Ungrouped plans (vertical list)

    private var ungroupedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ungrouped")
                .font(.title3.bold())
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(ungroupedPlans) { plan in
                    NavigationLink(value: plan) {
                        ungroupedPlanRow(plan)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func ungroupedPlanRow(_ plan: Plan) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(planGradients[plan.cardGradientIndex % planGradients.count].linear)
                .frame(width: 44, height: 44)
                .overlay {
                    if plan.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 5) {
                    ForEach(plan.sortedItems.prefix(6)) { item in
                        Image(systemName: item.workoutType.systemImage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if plan.items.count > 6 {
                        Text("+\(plan.items.count - 6)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
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
    @Query(sort: \PlanGroup.createdAt, order: .reverse) private var allGroups: [PlanGroup]

    private var favoriteGroups: [PlanGroup] { allGroups.filter { $0.isFavorite } }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

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
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(favoriteGroups) { group in
                            NavigationLink(value: group) {
                                PlanGroupCardView(group: group)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Favorite Groups")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PlanGroup.self) { group in
            PlanGroupDetailView(group: group)
        }
    }
}

// MARK: - Favorite Plans View

struct FavoritePlansView: View {
    @Query(sort: \Plan.createdAt, order: .reverse) private var allPlans: [Plan]

    private var favoritePlans: [Plan] { allPlans.filter { $0.isFavorite } }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

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
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(favoritePlans) { plan in
                            NavigationLink(value: plan) {
                                PlanCardView(plan: plan)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Favorite Plans")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Plan.self) { plan in
            PlanDetailView(plan: plan)
        }
    }
}

#Preview {
    PlansHomeView()
        .modelContainer(for: [Plan.self, PlanGroup.self, PlanItem.self], inMemory: true)
}
