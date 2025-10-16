//
//  RootView.swift
//  Deboogey
//
//  Created by Théo De Roy on 13/10/2025.
//

import SwiftUI
import AppKit

let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String

struct IdentifiableString: Identifiable { let id = UUID(); let value: String }

struct RootView: View {
    @State private var alertMessage: String? = nil
    @State private var showingLadybugLauncher = false

    var body: some View {
        VStack {
            Text(appName ?? "DEBOOGEY_DEVELOPMENT_STATE")
                .font(.largeTitle)
                .fontWeight(.black)
            Button(action: {
                do {
                    let output = try ws_overlayAlert.runOverlayHelper(arguments: ["enable"])
                    alertMessage = output.isEmpty ? "Complete." : output
                } catch {
                    alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
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
        .sheet(isPresented: $showingLadybugLauncher) {
            NavigationStack {
                LadybugLauncherView { action, domain in
                    do {
                        let output = try ladybugLauncher.runLadybugHelper(arguments: [action, domain])
                        alertMessage = output.isEmpty ? "Complete." : output
                    } catch {
                        alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            }
        }
        .padding()
    }
}

#Preview {
    RootView()
}
