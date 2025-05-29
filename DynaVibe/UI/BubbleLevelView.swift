// UI/Components/BubbleLevelView.swift
import SwiftUI

struct BubbleLevelView: View {
    // Angles in degrees
    let roll: Double
    let pitch: Double
    let isLevelThreshold: Double = 2.5 // Degrees within which it's considered "level"

    private var isEssentiallyLevel: Bool {
        abs(roll) < isLevelThreshold && abs(pitch) < isLevelThreshold
    }

    // Calculate bubble offset. Max visual offset is roughly radius of background - radius of bubble.
    // Let's say background radius is 20, bubble radius is 5. Max travel is 15.
    private var bubbleXOffset: CGFloat {
        let maxVisualOffset: CGFloat = 15.0
        let maxAngleConsidered: Double = 45.0 // Angles beyond this won't move bubble further
        let clampedRoll = max(-maxAngleConsidered, min(maxAngleConsidered, roll))
        return CGFloat(clampedRoll / maxAngleConsidered) * maxVisualOffset
    }

    private var bubbleYOffset: CGFloat {
        let maxVisualOffset: CGFloat = 15.0
        let maxAngleConsidered: Double = 45.0
        // Invert pitch for natural bubble movement (pitch up means bubble moves down on screen)
        let clampedPitch = max(-maxAngleConsidered, min(maxAngleConsidered, -pitch))
        return CGFloat(clampedPitch / maxAngleConsidered) * maxVisualOffset
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(isEssentiallyLevel ? Color.green.opacity(0.15) : Color(UIColor.systemGray5))
                .overlay(
                    Circle()
                        .strokeBorder(isEssentiallyLevel ? Color.green : Color.gray.opacity(0.6), lineWidth: 1)
                )
                .frame(width: 40, height: 40) // Main circle size

            // Center target lines (more subtle)
            Path { path in
                path.move(to: CGPoint(x: 15, y: 20)) // Shorter lines
                path.addLine(to: CGPoint(x: 25, y: 20))
                path.move(to: CGPoint(x: 20, y: 15))
                path.addLine(to: CGPoint(x: 20, y: 25))
            }
            .stroke(Color.gray.opacity(0.4), lineWidth: 0.8)

            // The bubble
            Circle()
                .fill(isEssentiallyLevel ? Color.green.opacity(0.8) : Color.blue.opacity(0.7))
                .frame(width: 10, height: 10) // Bubble size
                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0.5)
                .offset(x: bubbleXOffset, y: bubbleYOffset)
        }
        .frame(width: 40, height: 40) // Consistent frame for the whole ZStack
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.3), value: bubbleXOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.3), value: bubbleYOffset)
        .clipShape(Circle()) // Clip to ensure smooth edges if any part overflows due to offset animation
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Level")
        BubbleLevelView(roll: 0.5, pitch: -0.8)
        Text("Tilted: Roll 10, Pitch -15")
        BubbleLevelView(roll: 10, pitch: -15)
        Text("Tilted: Roll -30, Pitch 20")
        BubbleLevelView(roll: -30, pitch: 20)
        Text("Max Tilt")
        BubbleLevelView(roll: 50, pitch: -50)
    }
    .padding()
}
