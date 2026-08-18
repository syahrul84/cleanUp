import AppKit

/// Renders the live usage-bars menu bar icon: three vertical bars
/// (CPU, memory, disk) whose fill height tracks usage and whose color
/// signals load — green (low), blue (normal), red (high).
enum MenuBarBars {

    static func color(for fraction: Double, highFrom: Double = 0.75,
                      normalFrom: Double = 0.4) -> NSColor {
        if fraction >= highFrom { return .systemRed }
        if fraction >= normalFrom { return .systemBlue }
        return .systemGreen
    }

    /// Any metric passed as nil is omitted. Returns nil when no bars remain
    /// (caller falls back to the logo icon).
    static func image(cpu: Double?, mem: Double?, disk: Double?,
                      tempCelsius: Double? = nil, fanFraction: Double? = nil) -> NSImage? {
        let barWidth = 5.0, gap = 3.0, height = 16.0
        var bars: [(Double, NSColor)] = []
        if let cpu { bars.append((cpu, color(for: cpu))) }
        if let mem { bars.append((mem, color(for: mem))) }
        if let disk {
            // Disk fills slowly and living at 70% is normal — shift thresholds up.
            bars.append((disk, color(for: disk, highFrom: 0.9, normalFrom: 0.6)))
        }
        if let tempCelsius {
            let fraction = tempCelsius / 100
            bars.append((fraction, color(for: fraction, highFrom: 0.8, normalFrom: 0.6)))
        }
        if let fanFraction {
            bars.append((fanFraction, color(for: fanFraction)))
        }
        guard !bars.isEmpty else { return nil }
        let width = barWidth * Double(bars.count) + gap * Double(bars.count - 1)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            for (index, (fraction, color)) in bars.enumerated() {
                let x = Double(index) * (barWidth + gap)
                let track = NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barWidth, height: height),
                                         xRadius: 2, yRadius: 2)
                NSColor.gray.withAlphaComponent(0.35).setFill()
                track.fill()

                let fillHeight = max(2.5, height * min(max(fraction, 0), 1))
                let fill = NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barWidth, height: fillHeight),
                                        xRadius: 2, yRadius: 2)
                color.setFill()
                fill.fill()
            }
            return true
        }
        image.isTemplate = false // keep the colors
        return image
    }
}
