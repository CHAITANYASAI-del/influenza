import LedgerCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import Vision

/// Spec §54: Reading → Found → Matching → result summary.
struct ImportStatementSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable { case pick, reading, found(Int), matching, done(ImportJob), failed(String) }
    @State private var phase: Phase = .pick
    @State private var showPicker = false

    private static let types: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText, .pdf,
                                          UTType(filenameExtension: "ofx") ?? .data, UTType(filenameExtension: "qfx") ?? .data]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                content
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(AmbientBackground())
            .navigationTitle("Import statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: Self.types) { result in
                if case let .success(url) = result { Task { await run(url) } }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .pick:
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Download a statement from your bank or card app, then choose it here.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("CSV · OFX · QFX · PDF").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            PrimaryButton(title: "Choose statement", symbol: "folder") { showPicker = true }
            Label("Read on this iPhone. The file never leaves it.", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
        case .reading:
            ProgressView().controlSize(.large)
            Text("Reading statement…").font(.headline)
        case let .found(n):
            ProgressView().controlSize(.large)
            Text("Found \(n) records").font(.headline)
        case .matching:
            ProgressView().controlSize(.large)
            Text("Matching transactions…").font(.headline)
        case let .done(job):
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating)
            VStack(alignment: .leading, spacing: 10) {
                resultRow("\(job.newTransactions) new transactions", "plus.circle")
                if job.mergedIntoExisting > 0 { resultRow("\(job.mergedIntoExisting) matched to alerts you'd added", "link") }
                if job.duplicatesSkipped > 0 { resultRow("\(job.duplicatesSkipped) already in your ledger", "equal.circle") }
                if job.transfersExcluded > 0 { resultRow("\(job.transfersExcluded) transfers excluded", "arrow.left.arrow.right") }
                if job.refundsLinked > 0 { resultRow("\(job.refundsLinked) refunds linked", "arrow.uturn.backward") }
                if job.needsReview > 0 { resultRow("\(job.needsReview) need review", "exclamationmark.circle") }
            }
            .padding(20)
            .popSurface()
            PrimaryButton(title: "See where your money went") {
                model.selectedTab = 0
                dismiss()
            }
        case let .failed(message):
            Image(systemName: "questionmark.folder").font(.system(size: 52)).foregroundStyle(.orange)
            Text("We received this file, but couldn't understand it safely yet.").font(.headline).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            PrimaryButton(title: "Try another file", symbol: "folder") { showPicker = true }
        }
    }

    private func resultRow(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.body)
    }

    private func run(_ url: URL) async {
        withAnimation { phase = .reading }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { phase = .failed("The file couldn't be opened."); return }

        let name = url.lastPathComponent
        let isPDF = url.pathExtension.lowercased() == "pdf"
        let text: String? = isPDF ? await Self.pdfText(data) : (String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1))
        guard let text, !text.isEmpty else { phase = .failed("No readable text in this file."); return }

        let format: StatementFormat? = isPDF ? .pdfText : StatementDetector.detect(fileName: name, text: text) ?? .csv
        do {
            withAnimation { phase = .matching }
            let job = try store.importStatement(text: text, fileName: name, format: format, data: data)
            withAnimation { phase = .found(job.recordsSeen) }
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.snappy) { phase = .done(job) }
        } catch StatementParseError.noHeader {
            phase = .failed("We couldn't find date, description and amount columns.")
        } catch StatementParseError.noTransactions {
            phase = .failed("No transactions were found in this file.")
        } catch {
            phase = .failed("This format isn't supported yet.")
        }
    }

    /// PDFKit text first; Vision OCR for scanned pages (spec §35). On-device only.
    static func pdfText(_ data: Data) async -> String? {
        guard let doc = PDFDocument(data: data) else { return nil }
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        if text.filter(\.isLetter).count > 200 { return text }
        var ocr: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let image = page.thumbnail(of: CGSize(width: 1700, height: 2200), for: .mediaBox)
            if let cg = image.cgImage, let lines = try? await OCR.lines(cg) { ocr.append(lines.joined(separator: "\n")) }
        }
        return ocr.joined(separator: "\n")
    }
}

enum OCR {
    static func lines(_ image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, err in
                if let err { cont.resume(throwing: err); return }
                let obs = (req.results as? [VNRecognizedTextObservation] ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                cont.resume(returning: obs.compactMap { $0.topCandidates(1).first?.string })
            }
            request.recognitionLevel = .accurate
            do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { cont.resume(throwing: error) }
        }
    }
}
