import Foundation

struct CustomCategory: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var icon: String
    var colorName: String
    
    init(id: UUID = UUID(), name: String, icon: String, colorName: String) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorName = colorName
    }
    
    // Default system icons to choose from
    static let availableIcons: [String] = [
        "tag.fill", "creditcard.fill", "gift.fill", "house.fill", "briefcase.fill", 
        "wrench.fill", "gamecontroller.fill", "wineglass.fill", "cross.fill", 
        "pill.fill", "gym.bag.fill", "graduationcap.fill", "desktopcomputer", 
        "pawprint.fill", "leaf.fill", "bicycle", "bus.fill", "airplane.departure", 
        "cart.fill.badge.plus", "folder.fill", "tray.full.fill", "doc.text.fill", 
        "bell.fill", "hammer.fill", "paintbrush.fill", "scissors", "pencil", 
        "printer.fill", "envelope.fill", "calendar", "map.fill"
    ]
    
    // Default colors to choose from (using the app's existing color names)
    static let availableColors: [String] = [
        "lemonChiffon", "champagnePink", "teaRose", "pinkLavender", 
        "mauve", "jordyBlue", "nonPhotoBlue", "electricBlue", 
        "aquamarine", "celadon"
    ]
} 