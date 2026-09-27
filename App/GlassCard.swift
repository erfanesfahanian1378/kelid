import SwiftUI

/// A reusable "floating glass panel" look, matching Apple's Liquid Glass
/// design language (iOS 26+) — used across the app's own screens (Home,
/// Settings, etc.) so the app feels visually consistent with the modern
/// system look by default, rather than requiring the user to opt into a
/// *keyboard* theme to see anything different. Uses the real `glassEffect`
/// API where available, and falls back to a translucent material (the same
/// visual family, just without the real-time specular/refraction rendering)
/// on older OS versions so the app still looks reasonable there.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .padding(18)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .padding(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                )
        }
    }
}

/// The soft, colorful backdrop Liquid Glass panels are meant to float over
/// — a plain white/gray background makes even a real glass effect look
/// flat, since there's nothing behind it to refract.
struct GlassBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.35), Color.purple.opacity(0.25), Color.blue.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// Wraps this view in a `GlassCard` — shorthand for the common case of
    /// applying the whole-card treatment to one piece of content.
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        GlassCard(cornerRadius: cornerRadius) { self }
    }
}
