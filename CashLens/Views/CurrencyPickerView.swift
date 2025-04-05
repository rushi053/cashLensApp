import SwiftUI

struct CurrencyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Welcome message
                VStack(spacing: 16) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.appPrimary)
                    
                    Text("Welcome to CashLens")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Please select your preferred currency")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 40)
                
                // Currency list
                List {
                    ForEach(Expense.Currency.allCases, id: \.self) { currency in
                        Button(action: {
                            hapticFeedback(style: .medium)
                            viewModel.selectedCurrency = currency
                        }) {
                            HStack {
                                Text("\(currency.symbol) \(currency.rawValue) - \(currency.name)")
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if viewModel.selectedCurrency == currency {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.appPrimary)
                                }
                            }
                        }
                        .listRowBackground(
                            viewModel.selectedCurrency == currency ?
                            Color.appPrimary.opacity(0.1) :
                            Color.clear
                        )
                    }
                }
                .listStyle(InsetGroupedListStyle())
                
                // Continue button
                Button(action: {
                    hapticFeedback(style: .medium)
                    markCurrencyPickerAsShown()
                    dismiss()
                }) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: Color.appPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .navigationBarTitle("Select Currency", displayMode: .inline)
            .navigationBarItems(trailing: 
                Button(action: {
                    hapticFeedback(style: .medium)
                    markCurrencyPickerAsShown()
                    dismiss()
                }) {
                    Text("Done")
                        .fontWeight(.bold)
                        .foregroundColor(.appPrimary)
                }
            )
        }
    }
    
    private func markCurrencyPickerAsShown() {
        viewModel.hasShownCurrencyPicker = true
        UserDefaults.standard.set(true, forKey: "hasShownCurrencyPicker")
        UserDefaults.standard.synchronize()
        print("Currency picker marked as shown")
    }
    
    // MARK: - Haptic Feedback
    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

struct CurrencyPickerView_Previews: PreviewProvider {
    static var previews: some View {
        CurrencyPickerView(viewModel: ExpenseViewModel())
    }
} 