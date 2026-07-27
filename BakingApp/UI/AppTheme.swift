import SwiftUI
import UIKit

enum AppTheme {
    enum Colors {
        static let background = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1.0)
                : UIColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 1.0)
        })

        static let cardBackground = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.16, blue: 0.14, alpha: 1.0)
                : UIColor(red: 1.0, green: 0.99, blue: 0.97, alpha: 1.0)
        })

        static let primaryText = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.95, green: 0.91, blue: 0.85, alpha: 1.0)
                : UIColor(red: 0.28, green: 0.19, blue: 0.12, alpha: 1.0)
        })

        static let secondaryText = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.78, green: 0.73, blue: 0.67, alpha: 1.0)
                : UIColor(red: 0.43, green: 0.35, blue: 0.29, alpha: 1.0)
        })

        static let accent = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.83, green: 0.52, blue: 0.39, alpha: 1.0)
                : UIColor(red: 0.72, green: 0.40, blue: 0.27, alpha: 1.0)
        })
    }

    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 20
        static let screen: CGFloat = 20
    }

    enum Radius {
        static let card: CGFloat = 18
    }
}
