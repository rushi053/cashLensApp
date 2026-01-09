import SwiftUI

struct SummaryCard: View {
    let title: String
    let amount: Double
    let icon: String
    let color: Color
    @EnvironmentObject var viewModel: ExpenseViewModel
    var action: () -> Void
    
    private var cardHeight: CGFloat {
        // Keep cards visually consistent even when text is long (e.g., very large amounts).
        UIDevice.current.userInterfaceIdiom == .pad ? 170 : 150
    }
    
    init(title: String, amount: Double, icon: String, color: Color, action: @escaping () -> Void = {}) {
        self.title = title
        self.amount = amount
        self.icon = icon
        self.color = color
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(color)
                }
                
                // Title
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                
                // Amount
                Text(viewModel.formattedAmount(amount))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)                 // Prevent wrapping that changes card height
                    .minimumScaleFactor(0.55)     // Shrink font for very long numbers
                    .allowsTightening(true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: cardHeight, alignment: .topLeading)
            .background(Color.secondarySystemBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct SummaryCard_Previews: PreviewProvider {
    static var previews: some View {
        SummaryCard(
            title: "Total Expenses",
            amount: 1250.75,
            icon: "creditcard.fill",
            color: .blue
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
}