//
//  SettingsRootView.swift
//  Deboogey
//
//  Created by Théo De Roy on 26/10/2025.
//

import SwiftUI

struct SettingsRootView: View {
    @Environment(\.sipEnabled) private var sipEnabled
    @StateObject private var vars = PersistentVariables()

    var body: some View {
        TabView {
            VStack(alignment: .leading, spacing: 16) {
<<<<<<< HEAD
                Toggle("System-write notice on startup", isOn: $vars.pesterMeWithSipping)
                    .disabled(!sipEnabled)
=======
                Toggle("System-write notice on startup (when applicable)", isOn: $vars.pesterMeWithSipping)
>>>>>>> 050299f (Include RootView footer)
            }
            .padding(20)
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 360)
    }
}
