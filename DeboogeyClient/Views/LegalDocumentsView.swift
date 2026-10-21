//
//  LegalDocumentsView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 21/10/2026.
//

import SwiftUI
#if DEBOOGEY_MCE
import PDFKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
#endif

enum BundledLegalDocument: String, Identifiable {
    case license
#if DEBOOGEY_MCE
    case privacyPolicy
#endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .license:
            return L10n.t("License")
#if DEBOOGEY_MCE
        case .privacyPolicy:
            return L10n.t("Privacy Policy")
#endif
        }
    }

    var detail: String? {
        switch self {
        case .license:
            return L10n.t("GNU Affero General Public License v3")
#if DEBOOGEY_MCE
        case .privacyPolicy:
            return nil
#endif
        }
    }

    var bundleURL: URL? {
        switch self {
        case .license:
            return Bundle.main.url(forResource: "LICENSE", withExtension: nil)
#if DEBOOGEY_MCE
        case .privacyPolicy:
            return Bundle.main.url(forResource: "Privacy Policy (DeboogeyMCE)", withExtension: "pdf")
#endif
        }
    }
}

struct LegalDocumentReaderView: View {
    let document: BundledLegalDocument

    var body: some View {
        Group {
            if let url = document.bundleURL {
                switch document {
                case .license:
                    LicenseTextView(url: url)
#if DEBOOGEY_MCE
                case .privacyPolicy:
                    BundledPDFView(url: url)
#endif
                }
            } else {
                Text(L10n.t("Document unavailable"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(document.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private struct LicenseTextView: View {
    let url: URL

    private var text: String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? L10n.t("Document unavailable")
    }

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}

#if DEBOOGEY_MCE
private struct BundledPDFView: View {
    let url: URL

    var body: some View {
        PDFKitRepresentable(url: url)
    }
}

#if canImport(AppKit)
private struct PDFKitRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}
#elseif canImport(UIKit)
private struct PDFKitRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
#endif
#endif
