import SwiftUI

struct PlaybackControlsOverlay: View {
    var viewModel: LivePlayerViewModel
    let showSourceButton: Bool
    let showsTopBar: Bool
    let dismiss: DismissAction
    
    var body: some View {
        ZStack {
            // Dim background when controls visible
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.toggleControlsFromPlaybackTap()
                }
            
            VStack {
                if showsTopBar {
                    // Top bar
                    HStack {
                    Button { dismiss() } label: {
                        Label("Close", systemImage: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(.black.opacity(0.62))
                            .clipShape(Capsule())
                    }
                    .accessibilityIdentifier("close-live-player")
                    
                    Spacer()
                    
                    // Match badge
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            if let url = viewModel.event.homeBadgeURL ?? TeamBrandService.shared.badgeURL(for: viewModel.event.homeName, triggerSearch: true) {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFit()
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(width: 14, height: 14)
                            }
                            Text(shortCode(for: viewModel.event.homeName))
                                .font(.system(size: 13, weight: .bold))
                        }
                        
                        playbackTimingBadge
                        
                        HStack(spacing: 4) {
                            Text(shortCode(for: viewModel.event.awayName))
                                .font(.system(size: 13, weight: .bold))
                            
                            if let url = viewModel.event.awayBadgeURL ?? TeamBrandService.shared.badgeURL(for: viewModel.event.awayName, triggerSearch: true) {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFit()
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(width: 14, height: 14)
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        if showSourceButton {
                            Button {
                                viewModel.showSourceSelector = true
                                viewModel.scheduleAutoHide()
                            } label: {
                                Label("Sources", systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 44)
                                    .background(.black.opacity(0.62))
                                    .clipShape(Capsule())
                            }
                            .accessibilityLabel("Choose broadcast source")
                        }

                        if viewModel.isPictureInPictureAvailable && !viewModel.isUsingWebEmbed {
                            Button {
                                viewModel.togglePictureInPicture()
                            } label: {
                                Image(systemName: viewModel.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel(viewModel.isPictureInPictureActive ? "Stop Picture in Picture" : "Start Picture in Picture")
                        }
                        
                        Button {
                            viewModel.toggleFillMode()
                        } label: {
                            Image(systemName: viewModel.isFillMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(viewModel.isFillMode ? "Fit Video" : "Fill Screen")
                    }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                }
                
                Spacer()
                
                // Center play/pause
                if viewModel.isUsingWebEmbed {
                    Text("Web Stream")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.black.opacity(0.5)))
                } else {
                    Button {
                        viewModel.togglePlayPause()
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                            .frame(width: 70, height: 70)
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
                }
                
                Spacer()
                
                // Bottom — competition info
                HStack {
                    Text(viewModel.event.categoryDisplayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            viewModel.scheduleAutoHide()
        }
        .transition(.opacity)
    }
    
    private func shortCode(for team: String) -> String {
        let cleaned = team
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if cleaned.isEmpty {
            return "TEAM"
        }
        
        if cleaned.count == 1 {
            return String(cleaned[0].prefix(4)).uppercased()
        }
        
        let initials = cleaned.prefix(3).compactMap { $0.first }
        return String(initials).uppercased()
    }

    @ViewBuilder
    private var playbackTimingBadge: some View {
        let timing = viewModel.event.broadcastTiming()
        if timing == .live {
            LivePulse()
        } else {
            Text(timing.rawValue)
                .font(.fottyScaled(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .tracking(0.5)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.5)))
        }
    }
}
