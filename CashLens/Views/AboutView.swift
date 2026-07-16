import SwiftUI

/// AboutView — v2 redesign.
///
/// Calmer, scan-friendly hierarchy:
/// - A right-sized logo hero (no oversized circle wash).
/// - Sections live inside `cardSurface()` containers with semantic
///   section titles and consistent typography.
/// - Contact rows use the system-row pattern with leading icons rather
///   than chunky inset cards, so the whole screen reads as one cohesive
///   settings sub-page (Apple Settings → About style) instead of a
///   scrollable brochure.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    /// Same legal destinations as the paywall — Apple standard EULA for
    /// subscriptions, custom privacy page for the on-device story.
    private static let privacyPolicyURL = URL(string: "https://cashlens.app/privacy")!
    private static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "Version \(version) (\(build))"
    }

    private var whatsNewTitle: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        return "What's New in v\(version)"
    }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.xl) {
                    appHero

                    sectionCard(title: "About CashLens") {
                        Text("CashLens is a personal finance app for the rest of us. Track expenses, manage subscriptions, see where your money goes — calmly, privately, and entirely on your device.")
                            .font(.body)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    sectionCard(title: "Key Features") {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
                            featureRow(icon: "speedometer", text: "Today verdict — know you're on track at a glance")
                            featureRow(icon: "list.bullet.rectangle.portrait", text: "Activity timeline with smart search and calendar view")
                            featureRow(icon: "chart.line.uptrend.xyaxis", text: "Insights, forecasts, and trend breakdowns")
                            featureRow(icon: "target", text: "Budgets and alerts that nudge — never nag")
                            featureRow(icon: "arrow.clockwise.circle.fill", text: "Subscriptions with renewal reminders")
                            featureRow(icon: "doc.text.image.fill", text: "Receipt photos attached to any expense")
                            featureRow(icon: "tag.fill", text: "Custom categories, tags, and pinned summaries")
                            featureRow(icon: "shippingbox.fill", text: "Cross-device backup including receipt photos")
                            featureRow(icon: "lock.shield.fill", text: "All data stored locally — yours, always")
                        }
                    }

                    sectionCard(title: whatsNewTitle) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
                            featureRow(icon: "sparkles", text: "Redesigned Today, Activity, Insights, and You tabs")
                            featureRow(icon: "rectangle.stack.fill", text: "New elevated card system across the app")
                            featureRow(icon: "doc.text.image.fill", text: "Receipt photos with full archive backup")
                            featureRow(icon: "creditcard.fill", text: "Payment method tracking and donut chart")
                            featureRow(icon: "bell.badge.fill", text: "Proactive smart insight notifications (Pro)")
                        }

                        Text("Built around clarity, consistency, and respect for your attention.")
                            .font(Theme.Typography.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, Theme.Spacing.xs)
                    }

                    sectionCard(title: "Contact") {
                        VStack(spacing: 0) {
                            contactRow(
                                icon: "envelope.fill",
                                title: "Email",
                                value: "email@rushiraj.me",
                                url: "mailto:email@rushiraj.me"
                            )
                            Divider().padding(.leading, 38).opacity(0.4)
                            contactRow(
                                icon: "globe",
                                title: "Website",
                                value: "cashlens.app",
                                url: "https://cashlens.app/"
                            )
                        }
                    }

                    sectionCard(title: "Privacy") {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            Text("CashLens stores your data only on your device. Nothing leaves your phone unless you ask it to (via export or backup). No accounts, no servers, no analytics.")
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: Theme.Spacing.sm) {
                                Link("Privacy Policy", destination: Self.privacyPolicyURL)
                                Text("·")
                                    .foregroundColor(.secondary.opacity(0.5))
                                Link("Terms of Use", destination: Self.termsOfUseURL)
                            }
                            .font(.subheadline.weight(.semibold))
                            .tint(.appPrimary)
                        }
                    }

                    sectionCard(title: "Developer") {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Designed and built by Rushiraj Jadeja.")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("© 2026 Rushiraj Jadeja. All rights reserved.")
                                .font(Theme.Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitle("About", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(.appPrimary)
                }
            }
        }
    }

    // MARK: - Hero

    private var appHero: some View {
        VStack(spacing: Theme.Spacing.md) {
            HeroGlyph(systemName: "dollarsign.circle.fill", size: 58)

            VStack(spacing: 2) {
                Text("CashLens")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(versionString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.lg)
    }

    // MARK: - Section card scaffold

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.subsectionTitle)
                .foregroundColor(.primary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .cardSurface()
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.appPrimary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.appPrimary.opacity(0.12)))

            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func contactRow(icon: String, title: String, value: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appPrimary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.appPrimary.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text(value)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.tertiaryLabel)
            }
            .padding(.vertical, Theme.Spacing.sm + 2)
            .contentShape(Rectangle())
        }
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
