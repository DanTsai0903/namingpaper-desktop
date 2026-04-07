import SwiftUI
import PDFKit

struct PDFPreviewView: View {
    let url: URL
    @State private var zoomLevel: Double = 1.0
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            PDFKitView(url: url, zoomLevel: $zoomLevel, currentPage: $currentPage, totalPages: $totalPages)
                .onReceive(NotificationCenter.default.publisher(for: .navigateToPage)) { notification in
                    if let page = notification.userInfo?["page"] as? Int {
                        currentPage = min(page, totalPages)
                    }
                }

            // Controls bar
            HStack {
                // Page indicator
                Text("Page \(currentPage) of \(totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Zoom controls
                Button {
                    zoomLevel = max(0.25, zoomLevel - 0.25)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("-", modifiers: .command)

                Slider(value: $zoomLevel, in: 0.25...4.0, step: 0.25)
                    .frame(width: 120)

                Button {
                    zoomLevel = min(4.0, zoomLevel + 0.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("+", modifiers: .command)

                Text("\(Int(zoomLevel * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL
    @Binding var zoomLevel: Double
    @Binding var currentPage: Int
    @Binding var totalPages: Int

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        context.coordinator.pdfView = pdfView

        if let doc = pdfView.document {
            DispatchQueue.main.async {
                totalPages = doc.pageCount
            }
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != url {
            pdfView.document = PDFDocument(url: url)
            if let doc = pdfView.document {
                DispatchQueue.main.async {
                    totalPages = doc.pageCount
                    currentPage = 1
                }
            }
        }

        let newScale = CGFloat(zoomLevel)
        if abs(pdfView.scaleFactor - newScale) > 0.01 {
            pdfView.scaleFactor = newScale
        }

        // Navigate to a specific page if currentPage changed
        if let doc = pdfView.document,
           let currentPDFPage = pdfView.currentPage {
            let visibleIndex = doc.index(for: currentPDFPage)
            let targetIndex = currentPage - 1
            if targetIndex != visibleIndex, targetIndex >= 0, targetIndex < doc.pageCount,
               let targetPage = doc.page(at: targetIndex) {
                pdfView.go(to: targetPage)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PDFView?

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged() {
            guard let pdfView, let currentPDFPage = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            let pageIndex = doc.index(for: currentPDFPage)
            DispatchQueue.main.async {
                self.parent.currentPage = pageIndex + 1
            }
        }
    }
}
