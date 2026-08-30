import SwiftUI
import Combine

// MARK: - Football Loading Animation

struct FootballLoadingView: View {
    var size: CGFloat = 40
    var label: String = "Loading Pitch..."

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let angle = Angle.degrees((now.truncatingRemainder(dividingBy: 1.5)) / 1.5 * 360)
                let bounce = sin(now * 5.0) * 6.0

                ZStack {
                    // Outer glow
                    Circle()
                        .fill(FottyTheme.accent.opacity(0.15))
                        .frame(width: size * 1.5, height: size * 1.5)
                        .blur(radius: 10)

                    // The Ball
                    Image(systemName: "soccerball")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .foregroundStyle(FottyTheme.textPrimary)
                        .rotationEffect(angle)
                        .offset(y: bounce)
                }
            }

            if !label.isEmpty {
                Text(label)
                    .font(.fottyScaled(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(FottyTheme.accentText)
                    .tracking(1.0)
                    .opacity(0.8)
            }
        }
    }
}

// MARK: - Goal Celebration Particles

struct GoalCelebrationView: View {
    @State private var particles: [Particle] = []
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var color: Color
        var velocity: CGSize
        var opacity: Double = 1.0
        var rotation: Double
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                for particle in particles {
                    context.opacity = particle.opacity
                    context.drawLayer { ctx in
                        ctx.translateBy(x: particle.x, y: particle.y)
                        ctx.rotate(by: .degrees(particle.rotation))

                        // Draw a small football or square
                        let rect = CGRect(origin: .zero, size: CGSize(width: 8, height: 8))
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(particle.color))
                    }
                }
            }
        }
        .onAppear {
            createParticles()
        }
        .onReceive(timer) { _ in
            updateParticles()
        }
    }

    private func createParticles() {
        let colors: [Color] = [FottyTheme.accent, .white, FottyTheme.liveAccent]
        for _ in 0..<50 {
            let p = Particle(
                x: 200,
                y: 400,
                color: colors.randomElement() ?? FottyTheme.accent,
                velocity: CGSize(width: .random(in: -5...5), height: .random(in: -15...(-5))),
                rotation: .random(in: 0...360)
            )
            particles.append(p)
        }
    }

    private func updateParticles() {
        for i in 0..<particles.count {
            particles[i].x += particles[i].velocity.width
            particles[i].y += particles[i].velocity.height
            particles[i].velocity.height += 0.5 // Gravity
            particles[i].opacity -= 0.02
            particles[i].rotation += 5
        }
        particles.removeAll { $0.opacity <= 0 }
    }
}

// MARK: - Pitch Background Pattern

struct PitchPattern: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                FottyTheme.background

                // Mown Grass Stripes
                VStack(spacing: 0) {
                    ForEach(0..<10) { i in
                        Rectangle()
                            .fill(i % 2 == 0 ? FottyTheme.textPrimary.opacity(0.02) : Color.clear)
                            .frame(height: geo.size.height / 10)
                    }
                }

                // Pitch Markings
                Group {
                    // Center line
                    Rectangle()
                        .fill(FottyTheme.textPrimary.opacity(0.03))
                        .frame(height: 1)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    // Center circle
                    Circle()
                        .stroke(FottyTheme.textPrimary.opacity(0.03), lineWidth: 1)
                        .frame(width: geo.size.width * 0.3)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    func pitchBackground() -> some View {
        self.background(PitchPattern())
    }
}

#Preview {
    ZStack {
        PitchPattern()
        FootballLoadingView()
    }
    .preferredColorScheme(.dark)
}
