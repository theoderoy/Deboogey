//
//  RootView.swift
//  Deboogey
//
//  Created by Théo De Roy on 13/10/2025.
//

import SwiftUI

let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

struct IdentifiableString: Identifiable { let id = UUID(); let value: String }

struct RootView: View {
    @State private var alertMessage: String? = nil
    @State private var showingLadybugLauncher = false
    @State private var showingws_overlayLauncher = false
    @State private var showSystemWriteRefused = false
    @Environment(\.sipEnabled) private var sipEnabled
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack {
            HStack() {
                VStack(spacing: 8) {
                    Image("Icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)
                    
                    Text(appName ?? "DEBOOGEY_DEVELOPMENT_STATE")
                        .font(.largeTitle)
                        .fontWeight(.black)
                    Text((shortVersion.isEmpty ? "" : "\(shortVersion)") + (buildNumber.isEmpty ? "" : shortVersion.isEmpty ? "\(buildNumber)" : " \(buildNumber)"))
                        .font(.subheadline)
                        .bold()
                }
                VStack {
                    Group {
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
                    }
                    
                    Group {
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
                    }
                    .disabled(sipEnabled)
                }
                .padding()
            }
            
            if sipEnabled == true {
                Text("System write-dependent features have been disabled.").foregroundStyle(.secondary)
                    .padding(3)
                    .padding(.bottom, 8)
            }
            
            Link(destination: URL(string: "https://github.com/theoderoy")!) {
                Text("github.com/theoderoy")
                    .bold()
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
        .alert("System write-dependent features have been disabled.", isPresented: $showSystemWriteRefused) {
            Button("OK", role: .cancel) { }
            Button("Learn More") {
                if let url = URL(string: "https://support.apple.com/guide/security/secb7ea06b49/web") {
                    openURL(url)
                }
            }
        } message: {
            Text("Some features of this app require System Integrity Protection to be disabled.\n\nThis helps protect your Mac, so disable it if you understand the risks.")
        }
        .onAppear{
            if sipEnabled == true {
                DispatchQueue.main.async {
                    showSystemWriteRefused = true
                }
            }
        }
    }
}

#Preview {
    RootView()
}
