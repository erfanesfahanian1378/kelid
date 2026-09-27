import SwiftUI

/// Task 10.2's 5-step onboarding (§6.10).
struct OnboardingView: View {
    let onDone: () -> Void
    @State private var step = 0
    @State private var tryItText = ""

    private static let stepCount = 5

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                welcomeStep.tag(0)
                addKeyboardStep.tag(1)
                whyFullAccessStep.tag(2)
                tryItStep.tag(3)
                doneStep.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .animation(.default, value: step)

            HStack {
                if step > 0, step < Self.stepCount - 1 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step < Self.stepCount - 1 {
                    Button(step == 0 ? "Get started" : "Next") { step += 1 }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    private var welcomeStep: some View {
        OnboardingStepView(
            systemImage: "keyboard",
            title: "Welcome to Kelid",
            description: "A Persian and English keyboard with prediction, a clipboard manager, and snippets — built to never leave your phone."
        )
    }

    private var addKeyboardStep: some View {
        OnboardingStepView(
            systemImage: "gearshape.2",
            title: "Add the keyboard",
            description: "Open Settings, then General → Keyboard → Keyboards → Add New Keyboard → Kelid. "
                + "While you're there, turn on Allow Full Access."
        ) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var whyFullAccessStep: some View {
        OnboardingStepView(
            systemImage: "lock.shield",
            title: "Why Full Access?",
            description: "Full Access lets Kelid share your clipboard and personal dictionary with this app, "
                + "and play sounds and haptics as you type.\n\n"
                + "Kelid never connects to the internet — nothing you type or copy ever leaves your device."
        )
    }

    private var tryItStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.cursor")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Try it")
                .font(.title.bold())
            Text("Tap the field below, then tap the 🌐 globe key to switch to Kelid.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            TextField("Type something…", text: $tryItText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 40)
            Spacer()
        }
        .padding(.top, 40)
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("You're all set")
                .font(.title.bold())
            Text("You can revisit this guide any time from Home.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
        .padding(.horizontal, 40)
    }
}

private struct OnboardingStepView<Actions: View>: View {
    let systemImage: String
    let title: String
    let description: String
    @ViewBuilder var actions: Actions

    init(systemImage: String, title: String, description: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.systemImage = systemImage
        self.title = title
        self.description = description
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title.bold())
            Text(description)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            actions
            Spacer()
        }
        .padding(.top, 40)
    }
}
