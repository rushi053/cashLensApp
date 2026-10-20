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
    
    /// Flat list of every available icon, kept for backwards compatibility
    /// with screens that just iterate the full set. New UIs should prefer
    /// `iconGroups` so the picker can render meaningful sections.
    static var availableIcons: [String] {
        iconGroups.flatMap { $0.icons }
    }
    
    /// Themed icon catalogue used by the redesigned picker. Each group is
    /// a curated set of SF Symbols so the user can scan a category instead
    /// of hunting through one giant grid. Categories are intentionally
    /// kept small (8–12 icons) so each row reads as a deliberate menu.
    static let iconGroups: [IconGroup] = [
        IconGroup(name: "Food & Drink", icons: [
            "fork.knife", "cup.and.saucer.fill", "wineglass.fill",
            "takeoutbag.and.cup.and.straw.fill", "birthday.cake.fill",
            "carrot.fill", "leaf.fill", "mug.fill"
        ]),
        IconGroup(name: "Shopping", icons: [
            "cart.fill", "bag.fill", "tshirt.fill", "shippingbox.fill",
            "gift.fill", "tag.fill", "scissors", "sparkles"
        ]),
        IconGroup(name: "Transport", icons: [
            "car.fill", "bus.fill", "tram.fill", "bicycle",
            "airplane.departure", "fuelpump.fill", "ferry.fill",
            "scooter", "parkingsign.circle.fill"
        ]),
        IconGroup(name: "Home & Bills", icons: [
            "house.fill", "bed.double.fill", "lightbulb.fill", "wifi",
            "bolt.fill", "drop.fill", "flame.fill", "washer.fill",
            "trash.fill"
        ]),
        IconGroup(name: "Money", icons: [
            "creditcard.fill", "banknote.fill", "building.columns.fill",
            "chart.line.uptrend.xyaxis", "dollarsign.circle.fill",
            "percent", "arrow.left.arrow.right"
        ]),
        IconGroup(name: "Health & Fitness", icons: [
            "heart.fill", "stethoscope", "cross.case.fill", "pill.fill",
            "bandage.fill", "figure.run", "figure.walk", "dumbbell.fill",
            "sportscourt.fill"
        ]),
        IconGroup(name: "Entertainment", icons: [
            "tv.fill", "headphones", "music.note", "gamecontroller.fill",
            "film.fill", "ticket.fill", "guitars", "popcorn.fill"
        ]),
        IconGroup(name: "Travel", icons: [
            "globe", "map.fill", "location.fill", "suitcase.fill",
            "binoculars.fill", "mountain.2.fill", "moon.stars.fill",
            "sun.max.fill", "beach.umbrella.fill"
        ]),
        IconGroup(name: "Work & Study", icons: [
            "briefcase.fill", "graduationcap.fill", "book.fill",
            "desktopcomputer", "laptopcomputer", "pencil",
            "doc.text.fill", "calendar", "envelope.fill"
        ]),
        IconGroup(name: "Personal", icons: [
            "person.2.fill", "pawprint.fill", "camera.fill",
            "phone.fill", "message.fill", "heart.text.square.fill",
            "star.fill", "bookmark.fill", "shield.fill"
        ]),
        IconGroup(name: "Tools & Utility", icons: [
            "wrench.fill", "hammer.fill", "paintbrush.fill",
            "printer.fill", "folder.fill", "tray.full.fill",
            "lock.fill", "key.fill", "gearshape.fill"
        ])
    ]
    
    struct IconGroup: Hashable {
        let name: String
        let icons: [String]
    }
    
    /// Curated palette catalogue. The order here determines the picker
    /// display order — we keep warm tones first, then cool, then accents,
    /// because that's what feels natural when scanning a colour grid.
    static let availableColors: [String] = colorGroups.flatMap { $0.colors }
    
    /// Grouped colours used by the redesigned picker so the grid reads
    /// as a deliberate palette, not a random pile of swatches.
    static let colorGroups: [ColorGroup] = [
        ColorGroup(name: "Warm", colors: [
            "lemonChiffon", "goldenrod", "honey", "champagnePink",
            "apricot", "coral", "teaRose", "blush"
        ]),
        ColorGroup(name: "Cool", colors: [
            "mint", "sage", "celadon", "forest",
            "aquamarine", "seafoam", "ocean", "nonPhotoBlue",
            "electricBlue", "jordyBlue"
        ]),
        ColorGroup(name: "Accent", colors: [
            "periwinkle", "lavender", "mauve", "plum",
            "pinkLavender", "slate"
        ])
    ]
    
    struct ColorGroup: Hashable {
        let name: String
        let colors: [String]
    }
}

// MARK: - Import Extensions
extension CustomCategory {
    init(from json: [String: Any]) throws {
        guard let idString = json["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = json["name"] as? String,
              let icon = json["icon"] as? String,
              let colorName = json["colorName"] as? String else {
            throw ImportError.parseError("Invalid custom category data")
        }
        
        self.id = id
        self.name = name
        self.icon = icon
        self.colorName = colorName
    }
    
    init(fromCSV line: String) throws {
        let fields = parseCSVFields(line)
        guard fields.count >= 4 else {
            throw ImportError.parseError("Invalid CSV custom category format: expected 4 fields, got \(fields.count)")
        }
        
        guard let id = UUID(uuidString: parseCSVField(fields[0])) else {
            throw ImportError.parseError("Invalid CSV custom category ID: '\(parseCSVField(fields[0]))'")
        }
        
        self.id = id
        self.name = parseCSVField(fields[1])
        self.icon = parseCSVField(fields[2])
        self.colorName = parseCSVField(fields[3])
    }
}
