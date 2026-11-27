import SwiftUI

// MARK: - Classroom Sharing Pro Paywall Card (Embedded in StudyShareSheet when locked)

public struct ClassroomProUpgradeView: View {
    @ObservedObject var store: StoreManager
    let theme: ReadingTheme
    let studyName: String

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Respectful Mission Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Classroom Sharing Pro")
                            .font(.title3.weight(.bold))
                        Text("One-time unlock · No subscription · Forever yours")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("God’s Word, Apple Pencil journaling, Strong’s, dictionaries, and receiving shared lessons are always 100% free and ad-free. Classroom Pro unlocks teacher & group sharing tools and helps support independent development of Sword & Quill.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            // What's Included
            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "qrcode", color: .blue, title: "Instant Offline Classroom QR Codes", detail: "Project a full-screen QR code for Sunday School or small group — zero server, zero accounts.")
                featureRow(icon: "airplayaudio", color: .indigo, title: "AirDrop, Text & Email (.sqstudy)", detail: "Send complete study trails and margin notes to your spouse, class, or study group.")
                featureRow(icon: "doc.richtext", color: .orange, title: "Printable US-Letter Handout PDFs", detail: "Export clean, structured lesson outlines ready to print or share.")
                featureRow(icon: "gift.fill", color: .green, title: "Students & Classmates Import Free", detail: "Only the person exporting needs Pro — everyone who receives your lesson imports it free.")
            }
            .padding(14)
            .background(theme.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.dividerColor, lineWidth: 1))

            // Primary Purchase Button
            VStack(spacing: 10) {
                Button {
                    Task { await store.purchaseClassroomPro() }
                } label: {
                    HStack {
                        if store.isPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                            Text("Unlock Classroom Pro — \(store.classroomProDisplayPrice)")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(store.isPurchasing)

                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    Text("Restore Previous Purchase")
                        .font(.caption.weight(.semibold))
                }
                .disabled(store.isPurchasing)

                if let msg = store.statusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                if let thanks = store.lastThankYouMessage {
                    Text(thanks)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .multilineTextAlignment(.center)
                }
            }

            #if DEBUG
            Divider()
            HStack {
                Label("Dev Preview Mode", systemImage: "wrench.and.screwdriver")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(store.debugSimulateProUnlocked ? "Lock Pro (Test Paywall)" : "Unlock Pro (Preview)") {
                    store.debugSimulateProUnlocked.toggle()
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            #endif
        }
    }

    private func featureRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Support Sword & Quill Sheet (Classroom Pro + Optional Tip Jar)

public struct SupportSwordAndQuillSheet: View {
    @ObservedObject var store: StoreManager
    let theme: ReadingTheme
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Mission Banner
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.title)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Support Sword & Quill")
                                    .font(.title3.weight(.bold))
                                Text("100% Independent · Ad-Free · Zero Subscriptions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("We will never charge for God’s Word or put ads in your Bible. If Sword & Quill blesses your personal study or teaching, you can unlock Classroom Pro or leave an optional one-time tip below to help keep development going.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .padding(14)
                    .background(theme.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.dividerColor, lineWidth: 1))

                    if let thanks = store.lastThankYouMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                            Text(thanks)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if let status = store.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }

                    // Classroom Pro Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("CLASSROOM SHARING PRO")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if store.isProUnlocked {
                                Label("UNLOCKED", systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                        }

                        Text("Share studies with your Sunday School class, small group, or spouse via offline Classroom QR Codes, .sqstudy AirDrop packages, clickable links, and printable Handout PDFs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !store.isProUnlocked {
                            Button {
                                Task { await store.purchaseClassroomPro() }
                            } label: {
                                HStack {
                                    Image(systemName: "qrcode.viewfinder")
                                    Text("Unlock Classroom Pro — \(store.classroomProDisplayPrice)")
                                        .font(.subheadline.weight(.bold))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(store.isPurchasing)
                        }
                    }
                    .padding(14)
                    .background(theme.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.dividerColor, lineWidth: 1))

                    // Optional Tip Jar
                    VStack(alignment: .leading, spacing: 10) {
                        Text("LEAVE AN OPTIONAL TIP")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        ForEach(SupportTipTier.allCases) { tier in
                            HStack(spacing: 12) {
                                Image(systemName: tier.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(tier.accentColor)
                                    .frame(width: 38, height: 38)
                                    .background(tier.accentColor.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tier.title)
                                        .font(.subheadline.weight(.bold))
                                    Text(tier.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    Task { await store.purchaseTip(tier) }
                                } label: {
                                    Text(store.displayPrice(for: tier))
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(tier.accentColor)
                                .controlSize(.small)
                                .disabled(store.isPurchasing)
                            }
                            .padding(10)
                            .background(theme.canvasBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.dividerColor, lineWidth: 0.8))
                        }

                        Text("Optional one-time App Store tips help fund independent development of Sword & Quill (not a tax-deductible charitable donation).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .padding(14)
                    .background(theme.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.dividerColor, lineWidth: 1))

                    // Restore Purchases + Dev Toggle
                    HStack {
                        Button {
                            Task { await store.restorePurchases() }
                        } label: {
                            Label("Restore Purchases", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isPurchasing)

                        Spacer()

                        #if DEBUG
                        Button(store.debugSimulateProUnlocked ? "Dev: Lock Pro" : "Dev: Unlock Pro") {
                            store.debugSimulateProUnlocked.toggle()
                        }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.bordered)
                        #endif
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .navigationTitle("Support & Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
