import SwiftUI

struct FloatingAddButton: View {
    let action: () -> Void
    let isIPad: Bool
    
    init(action: @escaping () -> Void, isIPad: Bool = false) {
        self.action = action
        self.isIPad = isIPad
    }
    
    var body: some View {
        Button(action: {
            HapticManager.shared.impact(style: .medium)
            action()
        }) {
            ZStack {
                // Background circle with shadow
                Circle()
                    .fill(Color.mauve)
                    .frame(width: isIPad ? 66 : 56, height: isIPad ? 66 : 56)
                    .shadow(color: Color.mauve.opacity(0.3), radius: 8, x: 0, y: 4)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 2)
                
                // Plus icon
                Image(systemName: "plus")
                    .font(.system(size: isIPad ? 28 : 24, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: 1.0)
    }
}

struct FloatingAddButton_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.1)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FloatingAddButton(action: {})
                        .padding(.trailing, 20)
                        .padding(.bottom, 100)
                }
            }
        }
    }
} 