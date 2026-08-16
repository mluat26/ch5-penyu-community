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

/// How a nest's latest temperature reads for incubation.
///
/// Distinct from the `NestTemperatureStatus` in the add-nest flow, which uses
/// wider 24–32°C bounds for its accent colours. These narrower bounds are the
/// sex-ratio ones.
///
/// The thresholds decide sex ratio in real nests, so they are named here
/// rather than buried in a view: below 29°C skews male, above 31°C skews
/// female and risks the clutch.
enum NestIncubationStatus {
    case cold
    case healthy
    case hot
    case unknown

    init(temperatureC: Double?) {
        guard let temperatureC else { self = .unknown; return }
        if temperatureC < 29 { self = .cold }
        else if temperatureC > 31 { self = .hot }
        else { self = .healthy }
    }

    var systemImage: String {
        switch self {
        case .cold: "snowflake"
        case .healthy: "checkmark.circle"
        case .hot: "heat.waves"
        case .unknown: "exclamationmark.icloud"
        }
    }

    var tint: Color {
        switch self {
        case .cold: Color(hex: "#00C3D0")
        case .healthy: Color(hex: "#34C759")
        case .hot, .unknown: Color(hex: "#FF383C")
        }
    }
}

extension NestStatusPill {
    /// Figma draws an unreported temperature as "--" on the same red as a hot
    /// nest: a logger that stopped talking is a problem, not a neutral state.
    static func temperature(_ temperatureC: Double?) -> NestStatusPill {
        let status = NestIncubationStatus(temperatureC: temperatureC)
        return NestStatusPill(
            systemImage: status.systemImage,
            text: temperatureC.map { String(format: "%.1f°C", $0) } ?? "--",
            foreground: .white,
            background: status.tint
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
