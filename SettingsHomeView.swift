//
//  SettingsHomeView.swift
//  surge15
//
//  Placeholder for the future settings screen — measurement units, backups, etc.
//

import SwiftUI

struct SettingsHomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Coming Soon", systemImage: "gearshape.fill")
            } description: {
                Text("Measurement units (m/km ↔ miles) and backups will live here.")
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    SettingsHomeView()
}
