import LedgerCore
import PhotosUI
import SwiftUI

/// Receipt text (pasted) or a photo (on-device OCR). Enriches the matching
/// bank transaction or becomes its own entry (spec §20, §31).
struct ReceiptSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var item: PhotosPickerItem?
    @State private var showCamera = false
    @State private var reading = false
    @State private var outcome: IngestOutcome?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let outcome {
                        outcomeView(outcome)
                    } else {
                        Group {
                            HStack(spacing: 10) {
                                Button("Camera", systemImage: "camera.fill") { showCamera = true }
                                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                                PhotosPicker(selection: $item, matching: .images) { Label("Photo", systemImage: "photo") }
                                PasteButton(payloadType: String.self) { s in if let v = s.first { Task { @MainActor in text = v } } }
                            }
                            .buttonStyle(PopButtonStyle(kind: .dark, fullWidth: false))
                        }
                        if reading { ProgressView("Reading receipt on this iPhone…") }
                        TextField("Receipt text", text: $text, axis: .vertical)
                            .lineLimit(6...14).font(.callout.monospaced())
                            .padding(14).popSurface()
                        PrimaryButton(title: "Add receipt", symbol: "plus") { outcome = store.addReceipt(text) }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("A receipt adds detail (shop, items) to the matching bank transaction. It never changes the bank's amount.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
            .onChange(of: item) { _, newItem in
                Task {
                    guard let data = try? await newItem?.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                    await ocr(img)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in Task { await ocr(img) } }.ignoresSafeArea()
            }
        }
    }

    private func ocr(_ image: UIImage) async {
        guard let cg = image.cgImage else { return }
        reading = true
        defer { reading = false }
        if let lines = try? await OCR.lines(cg) { text = lines.joined(separator: "\n") }
    }

    @ViewBuilder private func outcomeView(_ o: IngestOutcome) -> some View {
        VStack(spacing: 14) {
            switch o {
            case .merged: Label("Matched to a transaction and added detail", systemImage: "link.circle.fill").font(.headline).foregroundStyle(.blue)
            case .added, .needsReview: Label("Added from receipt", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
            case .duplicate: Label("Already added", systemImage: "equal.circle.fill").font(.headline)
            case let .notFinancial(reason): Label("Couldn't find a total (\(reason))", systemImage: "questionmark.circle").font(.headline)
            }
            if let tx = o.transactionID.flatMap(store.transaction) { TransactionRow(tx: tx).padding(14).popSurface() }
            Button("Done") { dismiss() }.buttonStyle(PopButtonStyle(kind: .primary, fullWidth: false)).controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
