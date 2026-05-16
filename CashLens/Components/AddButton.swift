import SwiftUI

struct AddButton: View {
    var action: () -> Void
    var isIPad: Bool = false
    
    var body: some View {
        Button(action: {
            // Use a single medium tap for feedback
            HapticManager.shared.mediumTap()
            action()
        }) {
            ZStack {
                Circle()
                    .fill(Color.appPrimary)
                    .frame(width: isIPad ? 70 : 56, height: isIPad ? 70 : 56)
                    .shadow(color: Color.appPrimary.opacity(0.4), radius: isIPad ? 10 : 8, x: 0, y: 4)
                
                Image(systemName: "plus")
                    .font(.system(size: isIPad ? 28 : 22, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .accessibilityLabel("Add Expense")
    }
}

struct AddButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AddButton(action: {})
                .previewDisplayName("iPhone")
            
            AddButton(action: {}, isIPad: true)
                .previewDisplayName("iPad")
        }
        .previewLayout(.sizeThatFits)
        .padding()
    }
} 
