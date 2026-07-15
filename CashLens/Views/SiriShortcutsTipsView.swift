//
//  SiriShortcutsTipsView.swift
//  CashLens
//
//  Small discovery sheet opened from Profile → "Siri & Shortcuts".
//  Lists the zero-setup phrases registered by `CashLensShortcuts` so
//  users learn they can log hands-free. Design-system cards; no
//  configuration — App Shortcuts need none.
//
import SwiftUI

struct SiriShortcutsTipsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header

                    phraseGroup(
                        title: "Log an expense",
                        icon: "plus.circle.fill",
                        phrases: [
                            "Log an expense in CashLens",
                            "Add an expense to CashLens"
                        ],
                        footnote: "Siri asks how much you spent and what it was for, then picks a category automatically."
                    )

                    phraseGroup(
                        title: "Check your spending",
                        icon: "chart.bar.fill",
                        phrases: [
                            "How much did I spend today in CashLens",
                            "Check my spending in CashLens"
                        ],
                        footnote: "Hear today's and this month's totals without opening the app."
                    )

                    shortcutsAppNote
                }
                .padding()
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Color.systemBackground)
            .navigationTitle("Siri & Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // "Done" text action — matches every other nav-chrome
                // utility sheet (Categories, Color Theme, App Icon,
                // Export, Import) instead of the one-off X icon.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.15))
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.appPrimary)
            }
            .frame(width: 52, height: 52)

            Text("Log hands-free")
                .font(Theme.Typography.sectionTitle)
                .foregroundColor(.primary)

            Text("These phrases work out of the box — no setup needed. Just say them to Siri, or find them in the Shortcuts app.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func phraseGroup(title: String, icon: String, phrases: [String], footnote: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.appPrimary)
                Text(title)
                    .font(Theme.Typography.rowTitle.weight(.semibold))
                    .foregroundColor(.primary)
            }

            VStack(spacing: 0) {
                ForEach(Array(phrases.enumerated()), id: \.offset) { idx, phrase in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.appPrimary.opacity(0.7))
                        Text("Hey Siri, \(phrase.lowercased().prefix(1))\(phrase.dropFirst())")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)

                    if idx < phrases.count - 1 {
                        Divider()
                            .padding(.leading, Theme.Spacing.lg)
                    }
                }
            }
            .cardSurface()

            Text(footnote)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, Theme.Spacing.xs)
        }
    }

    private var shortcutsAppNote: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.appPrimary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Build your own")
                    .font(Theme.Typography.rowTitle.weight(.semibold))
                    .foregroundColor(.primary)
                Text("Both actions are available in the Shortcuts app, so you can chain them into automations — like logging your commute cost when you arrive at work.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.lg)
        .cardSurface()
    }
}

#Preview {
    SiriShortcutsTipsView()
}
