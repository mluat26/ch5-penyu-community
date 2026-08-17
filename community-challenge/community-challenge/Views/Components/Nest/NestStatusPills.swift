import SwiftUI

/// The pill vocabulary shared by the section list (Figma 166:2957) and the
/// nest detail screen (166:3082). Both read the same values, so they draw them
/// the same way rather than each inventing a style.
struct NestStatusPill: View {
    let systemImage: String
    let text: String
    var foreground: Color = .black
    var background: Color = Color(hex: "#B6B6B6").opacity(0.1)
    var border: Color?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .regular))

            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 30)
        .background(background, in: Capsule())
        .overlay {
            if let border {
                Capsule().stroke(border, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// Temperature judgement and colour live in `NestTemperature`, built from
// the infobook's thresholds, so one reading cannot look healthy on one
// screen and alarming on another.

extension NestStatusPill {
    /// Figma draws an unreported temperature as "--" on the same red as a hot
    /// nest: a logger that stopped talking is a problem, not a neutral state.
    static func temperature(_ temperatureC: Double?) -> NestStatusPill {
        let band = NestTemperature.Band(temperatureC: temperatureC)
        return NestStatusPill(
            systemImage: band.systemImage,
            text: NestTemperature.textWithUnit(temperatureC),
            foreground: .white,
            background: band.tint
        )
    }

    static func hatchCountdown(days: Int?) -> NestStatusPill {
        let text: String = switch days {
        case .none: "--"
        case .some(let value) where value <= 0: "Hatching now"
        case .some(let value): "Hatch in \(value) days"
        }
        return NestStatusPill(systemImage: "timer", text: text)
    }

    static func battery(level: Double?) -> NestStatusPill {
        NestStatusPill(
            systemImage: batterySymbol(for: level),
            text: level.map { "\(Int(($0 * 100).rounded()))%" } ?? "--",
            background: Color(hex: "#B6B6B6").opacity(0.1),
            border: Color(hex: "#D3D3D3")
        )
    }

    private static func batterySymbol(for level: Double?) -> String {
        guard let level else { return "battery.0percent" }
        return switch level {
        case ..<0.1: "battery.0percent"
        case ..<0.375: "battery.25percent"
        case ..<0.625: "battery.50percent"
        case ..<0.875: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
