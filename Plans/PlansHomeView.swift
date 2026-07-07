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

// MARK: - Favoritable

protocol Favoritable {
    var isFavorite: Bool { get }
}

extension Plan: Favoritable {}

// MARK: - HomeTabLayout

struct HomeTabLayout<
    ScrollItem: Identifiable,
    ListItem: Favoritable & Identifiable,
    ScrollCard: View,
    ListRow: View
>: View {
    let scrollTitle: String
    let scrollItems: [ScrollItem]
    let listTitle: String
    let listItems: [ListItem]
    @ViewBuilder var scrollCard: (ScrollItem) -> ScrollCard
    @ViewBuilder var listRow: (ListItem) -> ListRow

    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }
    private var pageBackground: Color {
        isLight ? Color(red: 0.961, green: 0.973, blue: 0.992) : Color(red: 0.027, green: 0.039, blue: 0.094)
    }
    private var rowBackground: Color {
        isLight ? .white : Color(red: 0.055, green: 0.078, blue: 0.188)
    }
    private var sectionLabelColor: Color {
        isLight ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color(red: 0.376, green: 0.647, blue: 0.980)
    }
    private var dividerColor: Color {
        isLight ? Color(red: 0.749, green: 0.859, blue: 0.996) : Color(red: 0.118, green: 0.227, blue: 0.541)
    }

    private var sortedListItems: [ListItem] {
        listItems.sorted { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !scrollItems.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader(scrollTitle).padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(scrollItems) { item in
                                    scrollCard(item)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !sortedListItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(listTitle).padding(.horizontal)
                        VStack(spacing: 0) {
                            ForEach(Array(sortedListItems.enumerated()), id: \.element.id) { idx, item in
                                listRow(item)
                                    .overlay(alignment: .bottom) {
                                        if idx < sortedListItems.count - 1 {
                                            dividerColor
                                                .frame(height: 0.5)
                                                .padding(.leading, 64)
                                        }
                                    }
                            }
                        }
                        .background(rowBackground, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(.vertical)
        }
        .background(pageBackground.ignoresSafeArea())
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(sectionLabelColor)
            .textCase(.uppercase)
    }
}

// MARK: - Plans Home

struct PlansHomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \PlanGroup.createdAt, order: .reverse) private var groups: [PlanGroup]
    @Query(sort: \Plan.createdAt, order: .reverse) private var allPlans: [Plan]

    @State private var showingCreateGroup = false
    @State private var showingCreatePlan  = false

    private var isLight: Bool { colorScheme == .light }
    private var headingColor: Color { isLight ? Color(red: 0.059, green: 0.090, blue: 0.165) : .white }
    private var rowIconColor: Color { isLight ? Color(red: 0.624, green: 0.690, blue: 0.831) : Color(red: 0.761, green: 0.804, blue: 0.894) }
    private var rowChevronColor: Color { isLight ? Color(red: 0.761, green: 0.804, blue: 0.894) : Color(red: 0.624, green: 0.690, blue: 0.831) }
    private var sectionLabelColor: Color { isLight ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color(red: 0.376, green: 0.647, blue: 0.980) }

    private var plansBySessionCount: [Plan] {
        allPlans.sorted { $0.surgeSessions.count > $1.surgeSessions.count }
    }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty && allPlans.isEmpty {
                    ContentUnavailableView {
                        Label("No Plans Yet", systemImage: "list.clipboard")
                    } description: {
                        Text("Tap + to create a group or build a standalone plan.")
                    }
                } else {
                    HomeTabLayout(
                        scrollTitle: "Groups",
                        scrollItems: groups,
                        listTitle: "All Plans",
                        listItems: plansBySessionCount
                    ) { group in
                        NavigationLink(value: group) {
                            PlanGroupCardView(group: group)
                        }
                        .buttonStyle(.plain)
                    } listRow: { plan in
                        NavigationLink(value: plan) {
                            planRow(plan)
                        }
                        .buttonStyle(.plain)
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
            .sheet(isPresented: $showingCreateGroup) {
                CreatePlanGroupView()
            }
            .sheet(isPresented: $showingCreatePlan) {
                CreatePlanView()
            }
            .onAppear {
                sanitizeGroupNames()
                sanitizePlanNames()
            }
            .onChange(of: groups.map(\.name)) { sanitizeGroupNames() }
            .onChange(of: allPlans.map(\.name)) { sanitizePlanNames() }
        }
    }

    private func sanitizeGroupNames() {
        for group in groups where group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            group.name = "Untitled Group"
        }
    }

    private func sanitizePlanNames() {
        for plan in allPlans where plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            plan.name = "Untitled Plan"
        }
    }

    private func planRow(_ plan: Plan) -> some View {
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
    }
}

// MARK: - Plan Color Picker Sheet

struct PlanColorPickerSheet: View {
    @Bindable var plan: Plan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                PlanCardView(plan: plan, featured: true)
                    .frame(maxWidth: 260)
                    .padding(.top, 8)

                GradientPickerView(selectedIndex: $plan.cardGradientIndex)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Edit Color")
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
