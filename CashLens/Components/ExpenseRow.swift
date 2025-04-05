import SwiftUI

struct ExpenseRow: View {
    let expense: Expense
    @EnvironmentObject var viewModel: ExpenseViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            // Category icon with proper handling for custom categories
            ZStack {
                Circle()
                    .fill(Color.forCategory(viewModel.categoryColor(for: expense)).opacity(0.3))
                    .frame(width: 40, height: 40)
                
                Image(systemName: viewModel.categoryIcon(for: expense))
                    .font(.system(size: 16))
                    .foregroundColor(Color.forCategory(viewModel.categoryColor(for: expense)))
            }
            
            // Expense details
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                // Use proper category display name
                Text(viewModel.categoryDisplayName(for: expense))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Amount and date
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(expense.currency.symbol)\(String(format: "%.2f", expense.amount))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(formattedDate(expense.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondarySystemBackground.opacity(0.5))
        .cornerRadius(12)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct ExpenseRow_Previews: PreviewProvider {
    static var previews: some View {
        ExpenseRow(expense: Expense.sampleData[0])
            .environmentObject(ExpenseViewModel())
            .padding()
            .previewLayout(.sizeThatFits)
    }
} 