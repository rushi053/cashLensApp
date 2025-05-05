import SwiftUI

struct SummaryCard: View {
    let title: String
    let amount: Double
    let icon: String
    let color: Color
    @EnvironmentObject var viewModel: ExpenseViewModel
    var action: () -> Void
    
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
                
                // Amount
                Text(viewModel.formattedAmount(amount))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondarySystemBackground)
            .cornerRadius(20)
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