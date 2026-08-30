import SwiftUI

struct PlaybackWarmupView: View {
    @Bindable var service: PlaybackWarmupService
    let source: StreamSource
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Background Pulse for atmosphere
            Circle()
                .fill(Color.blue.opacity(0.1))
                .blur(radius: 60)
                .scaleEffect(rotation == 360 ? 1.2 : 0.8)
                .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: rotation)

            VStack(spacing: 0) {
                // Top Branding
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.fottyScaled(size: 14, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                    
                    Text("SECURE P2P HANDSHAKE")
                        .font(.fottyScaled(size: 11, weight: .black))
                        .tracking(2)
                        .foregroundStyle(FottyTheme.textTertiary)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Central High-End Loader
                VStack(spacing: 24) {
                    ZStack {
                        // Outer Ring
                        Circle()
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                            .frame(width: 180, height: 180)
                        
                        // Pulsing core
                        Circle()
                            .fill(
                                RadialGradient(colors: [FottyTheme.accent.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 80)
                            )
                            .frame(width: 160, height: 160)
                            .scaleEffect(rotation == 360 ? 1.1 : 0.9)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: rotation)
                        
                        // Scanning line
                        Circle()
                            .trim(from: 0, to: 0.1)
                            .stroke(FottyTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 180, height: 180)
                            .rotationEffect(.degrees(rotation))
                            .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: rotation)
                        
                        VStack(spacing: 4) {
                            Text(primaryStatusValue)
                                .font(.fottyScaled(size: 44, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Text(primaryStatusLabel)
                                .font(.fottyScaled(size: 12, weight: .black))
                                .foregroundStyle(FottyTheme.accentText)
                                .tracking(1)
                        }
                    }
                    
                    Text(service.userFacingStatusMessage.uppercased())
                        .font(.fottyScaled(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // Network Intelligence Bar (The "Fix")
                intelligenceBar
                    .padding(.bottom, 20)
                
                // Footer
                Button(action: onCancel) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                        Text("ABORT CONNECTION")
                    }
                    .font(.fottyScaled(size: 12, weight: .black))
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.red.opacity(0.1))
                    .clipShape(Capsule())
                }
                .padding(.bottom, 40)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
    
    private var intelligenceBar: some View {
        HStack(spacing: 16) {
            intelligenceItem(icon: "waveform", value: warmupStateValue, label: "STATE", color: .green)
            
            Divider().frame(height: 20).background(Color.white.opacity(0.1))
            
            intelligenceItem(icon: "person.2.fill", value: peerValue, label: "PEERS")
            
            Divider().frame(height: 20).background(Color.white.opacity(0.1))
            
            intelligenceItem(icon: "square.stack.3d.down.right.fill", value: segmentValue, label: "CHUNKS")
            
            Divider().frame(height: 20).background(Color.white.opacity(0.1))
            
            intelligenceItem(icon: "bolt.fill", value: speedValue.replacingOccurrences(of: " kbps", with: "k"), label: "SPD")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(FottyTheme.surfaceElevated.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal)
    }
    
    private func intelligenceItem(icon: String, value: String, label: String, color: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.fottyScaled(size: 8, weight: .black))
                .foregroundStyle(FottyTheme.textTertiary)
            
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.fottyScaled(size: 10))
                    .foregroundStyle(color == .white ? FottyTheme.accentText : color)
                
                Text(value)
                    .font(.fottyScaled(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
        }
    }
    
    @State private var rotation: Double = 0

    private var status: MediaFlowStatus? {
        service.currentStatus
    }

    private var primaryStatusValue: String {
        if case .readyForPlayback = service.state {
            return "OK"
        }
        guard let status else { return "..." }
        if status.state.lowercased() == "ready" || status.firstSegmentReady || status.readySegmentCount > 0 {
            return "OK"
        }
        if let manifestTTFBMs = status.manifestTTFBMs {
            return "\(max(1, manifestTTFBMs / 1000))"
        }
        if status.state.lowercased() == "refreshing" {
            return "R"
        }
        return "..."
    }

    private var primaryStatusLabel: String {
        if case .readyForPlayback = service.state {
            return "PLAYABLE"
        }
        guard let status else { return "BROKER" }
        if status.state.lowercased() == "ready" || status.firstSegmentReady || status.readySegmentCount > 0 {
            return "PLAYABLE"
        }
        if status.manifestTTFBMs != nil {
            return "SECONDS"
        }
        if status.state.lowercased() == "refreshing" {
            return "REFRESH"
        }
        return "BROKER"
    }

    private var warmupStateValue: String {
        switch service.state {
        case .idle:
            return "IDLE"
        case .starting:
            return "STARTING"
        case .resolving:
            return "RESOLVING"
        case .warming:
            return "WARMING"
        case .peersFound:
            return "PEERS"
        case .bufferingOnServer:
            return "BUFFERING"
        case .firstSegmentReady:
            return "SEGMENT OK"
        case .readyForPlayback:
            return "READY"
        case .failed:
            return "FAILED"
        case .timedOut:
            return "TIMEOUT"
        }
    }

    private var sessionValue: String {
        let raw = status?.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return "--" }
        return raw.count > 8 ? String(raw.suffix(8)).uppercased() : raw.uppercased()
    }

    private var peerValue: String {
        if let count = status?.peerCount {
            return "\(count)"
        }
        if case .warming(let peers, _, _) = service.state {
            return "\(peers)"
        }
        if case .peersFound(let count) = service.state {
            return "\(count)"
        }
        return "--"
    }

    private var segmentValue: String {
        if let count = status?.readySegmentCount, count > 0 {
            return "\(count)"
        }
        if status?.firstSegmentReady == true {
            return "1+"
        }
        return "CHECK"
    }

    private var speedValue: String {
        let speed = status?.downloadSpeedKbps ?? 0
        if speed > 0 { return "\(Int(speed)) kbps" }
        if case .warming(_, let speedKbps, _) = service.state, speedKbps > 0 {
            return "\(Int(speedKbps)) kbps"
        }
        return "--"
    }

    private var bufferValue: String {
        let buffer = status?.bufferSeconds ?? 0
        if buffer > 0 { return "\(Int(buffer))s" }
        if case .warming(_, _, let bufferSeconds) = service.state, bufferSeconds > 0 {
            return "\(Int(bufferSeconds))s"
        }
        if case .bufferingOnServer(let seconds) = service.state, seconds > 0 {
            return "\(Int(seconds))s"
        }
        if service.warmupElapsedSeconds > 0 {
            return "\(Int(service.warmupElapsedSeconds))s"
        }
        return "--"
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.fottyScaled(size: 12))
                Text(title)
                    .font(.fottyScaled(size: 10, weight: .bold))
            }
            .foregroundColor(.secondary)
            
            Text(value)
                .font(.fottyScaled(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
