import SwiftUI

/// The single source of truth for how a nest temperature is judged and
/// coloured, anywhere in the app.
///
/// Values come from the Smart Nest infobook, section 2:
///
///   - Recommended incubation: 29–30 °C
///   - Acceptable range:       26–32 °C
///   - High-temperature warning: above 32–33 °C reduces hatching success
///     and increases embryo mortality
///
/// Sex determination follows the same scale: ≈26–28 °C skews male, ≈29 °C is
/// the pivotal ~1:1 point, and ≈30–32 °C skews female.
///
/// The infobook is explicit that these are project values which "should remain
/// configurable rather than being hard-coded as universal biological
/// constants" — exact thresholds vary by species and population. They are
/// named here so a future settings screen can override one place rather than
/// hunting colour literals through the views.
enum NestTemperature {
    /// Below this the nest is outside the acceptable incubation range.
    static let minimumAcceptableC: Double = 26

    /// The pivotal temperature: below skews male, above skews female.
    static let pivotalC: Double = 29

    /// Above this, hatching success drops and embryo mortality rises.
    static let maximumAcceptableC: Double = 32

    /// What the reading means at a glance.
    enum Band {
        /// No reading has arrived. The infobook is explicit that this must
        /// read as "No Data" rather than showing a stale value as current.
        case noData
        /// Below the pivotal temperature — cooler, male-skewing.
        case cool
        /// Within the acceptable band and above pivotal.
        case optimal
        /// Past the high-temperature warning.
        case hot

        init(temperatureC: Double?) {
            guard let temperatureC else { self = .noData; return }
            if temperatureC > NestTemperature.maximumAcceptableC {
                self = .hot
            } else if temperatureC < NestTemperature.pivotalC {
                self = .cool
            } else {
                self = .optimal
            }
        }

        /// The colours the Figma nest cards use. Every temperature in the app
        /// draws from here so one reading cannot look healthy on one screen
        /// and alarming on another.
        var tint: Color {
            switch self {
            case .noData: Color(hex: "#8E8E93")
            case .cool: Color(hex: "#00C3D0")
            case .optimal: Color(hex: "#34C759")
            case .hot: Color(hex: "#FF383C")
            }
        }

        var systemImage: String {
            switch self {
            case .noData: "exclamationmark.icloud"
            case .cool: "snowflake"
            case .optimal: "checkmark.circle"
            case .hot: "heat.waves"
            }
        }
    }

    /// Outside the acceptable 26–32 °C range entirely, which is the condition
    /// the infobook's monitoring logic calls Critical. Distinct from `Band`:
    /// a 27 °C nest is `cool` but still acceptable, while 24 °C is not.
    static func isCritical(temperatureC: Double?) -> Bool {
        guard let temperatureC else { return false }
        return temperatureC < minimumAcceptableC || temperatureC > maximumAcceptableC
    }

    /// One decimal place, or the "--" the design uses when nothing has been
    /// reported. Centralised so every screen writes an absent reading the same.
    static func text(_ temperatureC: Double?) -> String {
        temperatureC.map { String(format: "%.1f", $0) } ?? "--"
    }

    static func textWithUnit(_ temperatureC: Double?) -> String {
        temperatureC.map { String(format: "%.1f°C", $0) } ?? "--"
    }
}

/// What `nest_temperature_stats` reports for one nest over one window.
///
/// All three are optional because the window may hold no readings -- which is
/// the ordinary state for any nest whose logger has never reported. That is the
/// "--" the designs show, not a zero: `0°C` would render as a real measurement.
struct NestTemperatureStats: Hashable, Sendable {
    let avgC: Double?
    let maxC: Double?
    let minC: Double?
}
