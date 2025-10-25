//
//  RootView.swift
//  Deboogey
//
//  Created by Théo De Roy on 13/10/2025.
//

import SwiftUI

let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String

struct IdentifiableString: Identifiable { let id = UUID(); let value: String }

struct RootView: View {
    @State private var alertMessage: String? = nil
    @State private var showingLadybugLauncher = false
    @State private var showingws_overlayLauncher = false
    @Environment(\.sipEnabled) private var sipEnabled

    var body: some View {
        VStack {
            Text(appName ?? "DEBOOGEY_DEVELOPMENT_STATE")
                .font(.largeTitle)
                .fontWeight(.black)
            
            Button(action: {
                showingws_overlayLauncher = true
            }) {
                Label {
                    Text("WindowServer Diagnostics")
                } icon: {
                    Image(systemName: "macwindow")
                }
                .font(.headline)
                .padding(8)
                .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sipEnabled)
            
            if sipEnabled == true {
                Text("This feature is unavailable when csrutil is enabled.").foregroundStyle(.secondary)
                    .padding(3)
                    .padding(.bottom, 8)
            }
            
            Button(action: {
                showingLadybugLauncher = true
            }) {
                Label {
                    Text("Ladybug Interface")
                } icon: {
                    Image(systemName: "ladybug")
                }
                .font(.headline)
                .padding(8)
                .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            
            Link(destination: URL(string: "https://github.com/theoderoy")!) {
                Text("github.com/theoderoy")
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .sheet(isPresented: $showingws_overlayLauncher) {
            NavigationStack {
                ws_overlayLauncherView { argument in
                    print("ws_overlayLauncherView Requested: \(argument)")
                }
            }
        }
        .sheet(isPresented: $showingLadybugLauncher) {
            NavigationStack {
                LadybugLauncherView { action, domain in
                    print("LadybugLauncherView Requested: \(action) \(domain)")
                }
            }
        }
        .padding()
    }
}

#Preview {
    RootView()
}
