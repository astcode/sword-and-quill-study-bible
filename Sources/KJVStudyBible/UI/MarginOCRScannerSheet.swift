import PencilKit
import SwiftUI
import UIKit
import Vision

// MARK: - On-Device Margin Handwriting OCR & Reference Scanner (Bible Canvas)

public struct MarginOCRScannerSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isScanning: Bool = false
    @State private var recognizedText: String = ""
    @State private var detectedRefs: [CrossReference] = []
    @State private var statusMessage: String? = nil

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if viewModel.chapterDrawing.strokes.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "pencil.and.scribble")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No handwriting found in \(viewModel.currentLocationTitle)")
                            .font(.headline)
                        Text("Write notes or Scripture references like \"Rom 8:28\" or \"Ps 23:1-3\" in the margin with Apple Pencil, then tap Scan Margin Ink.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                } else if isScanning {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Scanning your Apple Pencil handwriting on-device...")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if let msg = statusMessage {
                                Text(msg)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(viewModel.theme.accentBlue)
                            }

                            // 1. Detected Scripture References Section
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Detected Scripture References (\(detectedRefs.count))", systemImage: "link")
                                        .font(.subheadline.weight(.bold))
                                    Spacer()
                                    if !detectedRefs.isEmpty {
                                        Button {
                                            for ref in detectedRefs {
                                                viewModel.pinCrossReference(ref)
                                            }
                                            dismiss()
                                        } label: {
                                            Label("Pin All to Journal", systemImage: "pin.fill")
                                                .font(.caption.weight(.semibold))
                                                .lineLimit(1)
                                        }
                                        .fixedSize(horizontal: true, vertical: false)
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .tint(viewModel.theme.accentBlue)
                                    }
                                }

                                if detectedRefs.isEmpty {
                                    Text("No verse citations (like \"Rom 8:28\" or \"John 3:16\") were detected in your handwriting. You can edit the text below and tap Re-detect Refs.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(detectedRefs) { ref in
                                        HStack(spacing: 8) {
                                            Text(ref.displayRef)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(viewModel.theme.accentBlue)
                                            Spacer()
                                            Button {
                                                dismiss()
                                                viewModel.openCrossRefPreview(ref)
                                            } label: {
                                                Text("Preview")
                                                    .font(.caption.weight(.semibold))
                                                    .lineLimit(1)
                                            }
                                            .fixedSize(horizontal: true, vertical: false)
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)

                                            Button {
                                                viewModel.pinCrossReference(ref)
                                            } label: {
                                                Label("Pin", systemImage: "pin")
                                                    .font(.caption.weight(.semibold))
                                                    .lineLimit(1)
                                            }
                                            .fixedSize(horizontal: true, vertical: false)
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                            .tint(viewModel.theme.accentBlue)
                                        }
                                        .padding(10)
                                        .background(viewModel.theme.panelBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(viewModel.theme.dividerColor, lineWidth: 1))
                                    }
                                }
                            }

                            Divider()

                            // 2. Editable Recognized Handwritten Text
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Recognized Handwriting", systemImage: "text.viewfinder")
                                        .font(.subheadline.weight(.bold))
                                    Spacer()
                                    Button("Re-detect Refs") {
                                        detectedRefs = viewModel.referenceDB.extractReferences(from: recognizedText, limit: 20)
                                    }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                TextEditor(text: $recognizedText)
                                    .font(.system(size: 15, design: .serif))
                                    .frame(minHeight: 170)
                                    .padding(6)
                                    .background(viewModel.theme.canvasBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(viewModel.theme.dividerColor, lineWidth: 1))

                                // Action Buttons
                                HStack(spacing: 10) {
                                    Button {
                                        viewModel.saveNote(
                                            type: .chapter,
                                            title: "\(viewModel.currentLocationTitle) Margin Notes",
                                            body: recognizedText,
                                            verse: viewModel.verses.first
                                        )
                                        dismiss()
                                    } label: {
                                        Label("Save as Note", systemImage: "note.text.badge.plus")
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                    .buttonStyle(.borderedProminent)
                                    .tint(viewModel.theme.accentBlue)
                                    .disabled(recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    Button {
                                        let text = recognizedText
                                        dismiss()
                                        viewModel.startClipToJournal(sourceLabel: "\(viewModel.currentLocationTitle) Margin OCR", text: text)
                                    } label: {
                                        Label("Clip to Journal", systemImage: "scissors")
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                    .buttonStyle(.bordered)
                                    .disabled(recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    Button {
                                        UIPasteboard.general.string = recognizedText
                                        viewModel.showToast("Copied recognized text")
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                    .buttonStyle(.bordered)
                                    .disabled(recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Scan Margin Ink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if !viewModel.chapterDrawing.strokes.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Rescan") { runOCR() }
                            .disabled(isScanning)
                    }
                }
            }
            .onAppear {
                if !viewModel.chapterDrawing.strokes.isEmpty && recognizedText.isEmpty {
                    runOCR()
                }
            }
        }
    }

    private func runOCR() {
        let drawing = viewModel.chapterDrawing
        guard !drawing.strokes.isEmpty else { return }
        isScanning = true
        statusMessage = nil

        let bounds = drawing.bounds.insetBy(dx: -24, dy: -24)
        let rendered = drawing.image(from: bounds, scale: 2.0)
        let renderer = UIGraphicsImageRenderer(size: rendered.size)
        let flatImage = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: rendered.size))
            rendered.draw(at: .zero)
        }
        guard let cgImage = flatImage.cgImage else {
            isScanning = false
            statusMessage = "Could not render handwriting image."
            return
        }

        Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            var lines: [String] = []
            do {
                try handler.perform([request])
                for obs in request.results ?? [] {
                    if let top = obs.topCandidates(1).first?.string {
                        lines.append(top)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.statusMessage = "OCR Error: \(error.localizedDescription)"
                }
                return
            }

            let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                self.isScanning = false
                self.recognizedText = joined
                self.detectedRefs = self.viewModel.referenceDB.extractReferences(from: joined, limit: 20)
                if joined.isEmpty {
                    self.statusMessage = "No legible handwriting recognized. Try slightly larger or darker strokes."
                } else {
                    self.statusMessage = "Recognized \(lines.count) line(s) and \(self.detectedRefs.count) Scripture reference(s)."
                }
            }
        }
    }
}
