import UIKit

class HapticManager {
    static let shared = HapticManager()
    
    // Cached generators for better performance
    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    private init() {
        // Pre-prepare generators for faster first-time response
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        heavyImpactGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }
    
    // Impact feedback with custom style
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .light:
            lightImpactGenerator.impactOccurred()
        case .medium:
            mediumImpactGenerator.impactOccurred()
        case .heavy:
            heavyImpactGenerator.impactOccurred()
        default:
            // For other styles, create a new generator (soft/rigid available in iOS 13+)
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }
    
    // Selection feedback
    func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare() // Prepare for next use
    }
    
    // Notification feedback
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare() // Prepare for next use
    }
    
    // Convenience methods for common interactions
    
    // Light tap for navigation and UI elements
    func lightTap() {
        lightImpactGenerator.impactOccurred()
        lightImpactGenerator.prepare() // Prepare for next use
    }
    
    // Medium tap for selections and toggles
    func mediumTap() {
        mediumImpactGenerator.impactOccurred()
        mediumImpactGenerator.prepare() // Prepare for next use
    }
    
    // Heavy tap for important actions
    func heavyTap() {
        heavyImpactGenerator.impactOccurred()
        heavyImpactGenerator.prepare() // Prepare for next use
    }
    
    // Success feedback for completed actions
    func success() {
        notification(type: .success)
    }
    
    // Warning feedback for alerts
    func warning() {
        notification(type: .warning)
    }
    
    // Error feedback for errors
    func error() {
        notification(type: .error)
    }
    
    // Selection feedback for picker changes
    func selectionChanged() {
        selection()
    }
} 