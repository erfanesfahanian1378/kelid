#if canImport(UIKit)
    import KelidSettings
    import SwiftUI

    /// Task 4.3's resize-mode overlay (§6.3.7): edge handles, preset chips,
    /// a live readout, Reset and Done. Hosted by `KeyboardViewController` via
    /// `UIHostingController` — `KeyboardController` only ever hands this a
    /// `ResizeSession` and two callbacks, never touching SwiftUI itself
    /// (rule 5.1.15: engine/controller code stays UIKit-adjacent, not
    /// framework-specific beyond that).
    public struct ResizeOverlayView: View {
        @Bindable var session: ResizeSession
        let onDone: () -> Void
        let onReset: () -> Void

        /// Handle-local drag state — reset per gesture so each drag's
        /// translation is measured from where *that* drag started, matching
        /// `ResizeSession`'s own "total translation since gesture start"
        /// contract.
        @State private var activeDrag: Edge?

        public init(session: ResizeSession, onDone: @escaping () -> Void, onReset: @escaping () -> Void) {
            self.session = session
            self.onDone = onDone
            self.onReset = onReset
        }

        public var body: some View {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()

                VStack(spacing: 10) {
                    Spacer()
                    Text(session.readoutText)
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                    presetChips
                    controlButtons
                        .padding(.bottom, 10)
                }

                topHandle
                bottomHandle
                HStack {
                    leftEdgeHandle
                    Spacer()
                    rightEdgeHandle
                }
                if session.oneHanded != .off {
                    centerSwitchHandle
                }
            }
        }

        private var presetChips: some View {
            HStack(spacing: 8) {
                ForEach(ResizePreset.allCases, id: \.self) { preset in
                    Button(preset.label) { session.applyPreset(preset) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }

        private var controlButtons: some View {
            HStack {
                Button("Reset", role: .destructive, action: onReset)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
        }

        // MARK: - Handles (§6.3.7)

        private var topHandle: some View {
            VStack {
                handleBar(width: 60)
                    .contentShape(Rectangle().inset(by: -12)) // easier to grab than the visible bar alone
                    .gesture(dragGesture(.top))
                Spacer()
            }
            .padding(.top, 4)
        }

        private var bottomHandle: some View {
            VStack {
                Spacer()
                handleBar(width: 60)
                    .contentShape(Rectangle().inset(by: -12))
                    .gesture(dragGesture(.bottom))
            }
            .padding(.bottom, 90) // clears the readout/chips/buttons stacked at the bottom
        }

        private var leftEdgeHandle: some View {
            handleBar(width: 40)
                .rotationEffect(.degrees(90))
                .frame(width: 24)
                .contentShape(Rectangle().inset(by: -12))
                .gesture(dragGesture(.left))
        }

        private var rightEdgeHandle: some View {
            handleBar(width: 40)
                .rotationEffect(.degrees(90))
                .frame(width: 24)
                .contentShape(Rectangle().inset(by: -12))
                .gesture(dragGesture(.right))
        }

        /// §6.3.7's "center drag (one-handed only) → switch side (snaps)" —
        /// a tap-to-snap here rather than a continuous drag value, since the
        /// action itself ("switch side") is discrete.
        private var centerSwitchHandle: some View {
            Image(systemName: "arrow.left.arrow.right")
                .padding(10)
                .background(.thinMaterial, in: Circle())
                .onTapGesture { session.switchOneHandedSide() }
        }

        private func handleBar(width: CGFloat) -> some View {
            Capsule()
                .fill(.secondary)
                .frame(width: width, height: 5)
        }

        private enum Edge { case top, bottom, left, right }

        private func dragGesture(_ edge: Edge) -> some Gesture {
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if activeDrag != edge {
                        activeDrag = edge
                        session.beginDrag()
                    }
                    switch edge {
                    case .top:
                        session.applyTopDrag(totalTranslationY: value.translation.height)
                    case .bottom:
                        session.applyBottomDrag(totalTranslationY: value.translation.height)
                    case .left:
                        session.applyLeftEdgeDrag(totalTranslationX: value.translation.width, viewWidth: screenWidthHint)
                    case .right:
                        session.applyRightEdgeDrag(totalTranslationX: value.translation.width, viewWidth: screenWidthHint)
                    }
                }
                .onEnded { _ in activeDrag = nil }
        }

        /// `GeometryReader`-free approximation: the resize overlay always
        /// spans the full keyboard width, and one-handed's own `contentWidth
        /// ≥ 240pt` clamp (§6.3.3) already keeps the ratio sane even if this
        /// is slightly off for an unusual device width.
        private var screenWidthHint: CGFloat {
            UIScreen.main.bounds.width
        }
    }
#endif
