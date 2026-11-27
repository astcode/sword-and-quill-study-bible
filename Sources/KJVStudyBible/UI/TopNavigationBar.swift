import SwiftUI

public struct TopNavigationBar: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isCompact: Bool { hSizeClass == .compact }

    public var body: some View {
        HStack(spacing: isCompact ? 6 : 12) {
            // Left group: Main Menu + Extensible Reference Dropdown + Mode/Panel Dropdown + Search
            HStack(spacing: isCompact ? 6 : 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showMainMenu.toggle()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("Main Menu")

                // Extensible Top-Left Dropdown 1: Controls what shows in the Left Study Desk
                Menu {
                    Section("Left Study Desk") {
                        ForEach(LeftPanelTab.allCases) { tab in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.openLeftPanel(tab: tab)
                                }
                            } label: {
                                Label(tab.rawValue, systemImage: tab.systemImage)
                            }
                        }
                        Divider()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if viewModel.showReferencePanel {
                                    viewModel.toggleReferencePanel()
                                }
                            }
                        } label: {
                            Label("Close Study Panel", systemImage: "sidebar.left")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.showReferencePanel ? viewModel.leftPanelTab.systemImage : "sidebar.left")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.75)
                    }
                    .foregroundStyle(viewModel.showReferencePanel ? viewModel.theme.accentBlue : viewModel.theme.primaryText)
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .background(viewModel.showReferencePanel ? viewModel.theme.accentBlue.opacity(0.14) : viewModel.theme.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(viewModel.showReferencePanel ? viewModel.theme.accentBlue.opacity(0.45) : viewModel.theme.dividerColor, lineWidth: 0.9)
                    )
                }
                .accessibilityLabel("Study Desk: \(viewModel.showReferencePanel ? viewModel.leftPanelTab.rawValue : "Off")")

                // Extensible Top-Left Dropdown 2: Workspace Mode & Independent Panel Toggles
                Menu {
                    Section("Workspace Modes") {
                        ForEach(WorkspaceMode.allCases) { mode in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.applyMode(mode)
                                }
                            } label: {
                                Label(mode.rawValue, systemImage: mode.systemImage)
                            }
                        }
                    }
                    Section("Toggle Panels") {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.toggleReferencePanel()
                            }
                        } label: {
                            Label(
                                viewModel.showReferencePanel ? "Close Reference Panel" : "Open Reference Panel",
                                systemImage: "sidebar.left"
                            )
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.toggleJournalPanel()
                            }
                        } label: {
                            Label(
                                viewModel.showJournalPanel ? "Close Journal Margin" : "Open Journal Margin",
                                systemImage: "sidebar.right"
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.workspaceMode.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.75)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .background(viewModel.theme.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(viewModel.theme.dividerColor, lineWidth: 0.9)
                    )
                }
                .accessibilityLabel("Workspace Mode: \(viewModel.workspaceMode.rawValue)")

                Button {
                    viewModel.showSearchSheet = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("Search Scripture")
            }

            Spacer()

            // Center: Previous / Next Chapter arrows flanking the Book & Chapter selector
            HStack(spacing: isCompact ? 6 : 10) {
                let isAtGenesis1 = viewModel.currentBookId <= 1 && viewModel.currentChapter <= 1
                let isAtRev22 = viewModel.currentBookId >= 66 && viewModel.currentChapter >= (viewModel.currentBook?.chapterCount ?? 22)

                Button {
                    viewModel.previousChapter()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Circle().stroke(viewModel.theme.dividerColor, lineWidth: 1.1))
                }
                .disabled(isAtGenesis1)
                .opacity(isAtGenesis1 ? 0.3 : 1.0)
                .accessibilityLabel("Previous Chapter")

                Button {
                    viewModel.showScripturePicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.currentLocationTitle)
                            .font(.system(size: isCompact ? 17 : 20, weight: .semibold, design: .serif))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(viewModel.theme.primaryText)
                    .padding(.horizontal, isCompact ? 10 : 14)
                    .padding(.vertical, 6)
                    .background(viewModel.theme.panelBackground.opacity(0.6))
                    .clipShape(Capsule())
                }

                Button {
                    viewModel.nextChapter()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Circle().stroke(viewModel.theme.dividerColor, lineWidth: 1.1))
                }
                .disabled(isAtRev22)
                .opacity(isAtRev22 ? 0.3 : 1.0)
                .accessibilityLabel("Next Chapter")
            }

            Spacer()

            // Right group: KJV Badge + Study Trail Dropdown
            HStack(spacing: isCompact ? 6 : 10) {
                if !isCompact {
                    Text("KJV")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .tracking(1.2)
                        .foregroundStyle(viewModel.theme.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(viewModel.theme.dividerColor, lineWidth: 1)
                        )
                }

                // Top-Right Studies Dropdown (Named Study Sessions + Study Trail + Link to Bible Ink)
                Menu {
                    Button {
                        viewModel.showNewStudySheet = true
                    } label: {
                        Label("New Study...", systemImage: "plus.circle.fill")
                    }

                    if let active = viewModel.activeStudy {
                        Divider()
                        Section("Active: \(active.name)") {
                            Button {
                                viewModel.showStudyTrailSheet = true
                            } label: {
                                Label("View Study Trail (\(viewModel.activeStudyTrail.count))", systemImage: "list.bullet.rectangle")
                            }
                            Button {
                                viewModel.showAddStudyLinkSheet = true
                            } label: {
                                Label("Link Study / Add Note to Bible Ink", systemImage: "pin.fill")
                            }
                            Button {
                                viewModel.exitActiveStudy()
                            } label: {
                                Label("Exit Study Session", systemImage: "pause.circle")
                            }
                        }
                    }

                    if !viewModel.studySessions.isEmpty {
                        Divider()
                        Section("Saved Studies") {
                            ForEach(viewModel.studySessions) { study in
                                Button {
                                    if viewModel.activeStudy?.id == study.id {
                                        viewModel.showStudyTrailSheet = true
                                    } else {
                                        viewModel.activateStudy(study)
                                    }
                                } label: {
                                    if viewModel.activeStudy?.id == study.id {
                                        Label("\(study.name) (Active)", systemImage: "checkmark.circle.fill")
                                    } else {
                                        Label(study.name, systemImage: "book.pages")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.activeStudy != nil {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                        }
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.75)
                    }
                    .foregroundStyle(viewModel.activeStudy != nil ? .white : viewModel.theme.primaryText)
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .background(viewModel.activeStudy != nil ? viewModel.theme.accentBlue : viewModel.theme.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(viewModel.activeStudy != nil ? viewModel.theme.accentBlue : viewModel.theme.dividerColor, lineWidth: 0.9)
                    )
                }
                .accessibilityLabel(viewModel.activeStudy != nil ? "Active Study: \(viewModel.activeStudy!.name)" : "Study Trails")
            }
        }
        .foregroundStyle(viewModel.theme.primaryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(viewModel.theme.chromeBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(viewModel.theme.dividerColor).frame(height: 1)
        }
    }
}
