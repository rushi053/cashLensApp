import SwiftUI

struct SplashScreenView: View {
    @State private var isAnimating = false
    @Binding var showSplash: Bool
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.mauve, Color.jordyBlue]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                // App logo
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 160, height: 160)
                    
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "creditcard.viewfinder")
                        .font(.system(size: 70, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(isAnimating ? 1.0 : 0.6)
                .opacity(isAnimating ? 1.0 : 0.7)
                
                // App name
                Text("CashLens")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .offset(y: isAnimating ? 0 : 20)
                
                // Tagline
                Text("Your financial clarity companion")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .offset(y: isAnimating ? 0 : 15)
                    .padding(.top, -10)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8, blendDuration: 0.5).delay(0.2)) {
                isAnimating = true
            }
            
            // Dismiss the splash screen after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showSplash = false
                }
            }
        }
    }
}

struct SplashScreenView_Previews: PreviewProvider {
    static var previews: some View {
        SplashScreenView(showSplash: .constant(true))
    }
} 