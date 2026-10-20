import Foundation

public enum WeightUnit: String, CaseIterable, Codable, Sendable {
    case kg
    case lbs

    public var abbrev: String { rawValue }
}

/// Unit conversion + slider ranges. Mirrors `WeightUnits` in the Android app.
public enum WeightUnits {
    public static let lbsPerKg: Float = 2.2046226218
    public static let minGapKg: Float = 0.5
    public static let sliderStep: Float = 0.5

    public static func kgToDisplay(_ kg: Float, _ unit: WeightUnit) -> Float {
        switch unit {
        case .kg: kg
        case .lbs: kg * lbsPerKg
        }
    }

    public static func displayToKg(_ display: Float, _ unit: WeightUnit) -> Float {
        switch unit {
        case .kg: display
        case .lbs: display / lbsPerKg
        }
    }

    public static func snapToStep(_ value: Float) -> Float {
        (value / sliderStep).rounded() * sliderStep
    }

    public static func minSliderMax(_ unit: WeightUnit) -> Float {
        snapToStep(kgToDisplay(30, unit))
    }

    public static func scrollSliderMin(_ unit: WeightUnit) -> Float {
        snapToStep(kgToDisplay(1, unit))
    }

    public static func scrollSliderMax(_ unit: WeightUnit) -> Float {
        snapToStep(kgToDisplay(50, unit))
    }

    public static func format(_ kg: Float, _ unit: WeightUnit) -> String {
        let display = kgToDisplay(kg, unit)
        let rounded = (display * 10).rounded() / 10
        return String(format: "%.1f %@", rounded, unit.abbrev)
    }
}
