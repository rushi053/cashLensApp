import SwiftUI
import Foundation

struct CurrencyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    var isInitialSetup: Bool = false
    @State private var searchText = ""
    @State private var selectedRegion: CurrencyRegion = .all
    
    var filteredCurrencies: [Expense.Currency] {
        let regionCurrencies = selectedRegion.currencies
        let uniqueCurrencies = Array(Set(regionCurrencies)).sorted { $0.rawValue < $1.rawValue }
        if searchText.isEmpty {
            return uniqueCurrencies
        }
        return uniqueCurrencies.filter { currency in
            currency.rawValue.localizedCaseInsensitiveContains(searchText) ||
            currency.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Welcome header for initial setup
                if isInitialSetup {
                    VStack(spacing: 8) {
                        Text("💰")
                            .font(.system(size: 40))
                        Text("Select your preferred currency")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondarySystemBackground.opacity(0.5))
                }
                
                // Search bar
                SearchBar(text: $searchText, placeholder: "Search currencies...")
                    .padding()
                
                // Region picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(CurrencyRegion.allCases, id: \.self) { region in
                            Button(action: {
                                hapticFeedback(style: .light)
                                selectedRegion = region
                            }) {
                                Text(region.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(selectedRegion == region ? .bold : .regular)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedRegion == region ?
                                        Color.appPrimary :
                                        Color.secondarySystemBackground
                                    )
                                    .foregroundColor(
                                        selectedRegion == region ?
                                        .white :
                                        .primary
                                    )
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
                // Currency list
                ScrollViewReader { proxy in
                    List {
                        ForEach(filteredCurrencies, id: \.rawValue) { currency in
                            Button(action: {
                                hapticFeedback(style: .medium)
                                viewModel.selectedCurrency = currency
                            }) {
                                HStack {
                                    Text(currency.symbol)
                                        .font(.title2)
                                        .frame(width: 40)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(currency.rawValue)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text(currency.name)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
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
                            .id(currency.rawValue)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(viewModel.selectedCurrency.rawValue, anchor: .center)
                        }
                    }
                }
            }
            .navigationBarTitle(isInitialSetup ? "Choose Your Currency" : "Select Currency", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        hapticFeedback(style: .medium)
                        dismiss()
                    }) {
                        Text(isInitialSetup ? "Continue" : "Done")
                            .fontWeight(.bold)
                            .foregroundColor(.appPrimary)
                    }
                }
            }
            .interactiveDismissDisabled(isInitialSetup) // Prevent swipe to dismiss on initial setup
        }
    }
    
    // MARK: - Haptic Feedback
    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
    }
}

struct CurrencyPickerView_Previews: PreviewProvider {
    static var previews: some View {
        CurrencyPickerView(viewModel: ExpenseViewModel())
    }
} 