import SwiftUI

struct WrappedEntryBanner: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.mauve.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.mauve)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("CashLens Wrapped")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("This month and Diwali, as a story")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color.mauve)
            }
            .padding(16)
            .background(Color.secondarySystemBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("CashLens Wrapped")
        .accessibilityHint("Opens your spending story")
    }
}

struct WrappedEntryBanner_Previews: PreviewProvider {
    static var previews: some View {
        WrappedEntryBanner(action: {})
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
