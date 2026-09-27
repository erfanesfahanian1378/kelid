import SwiftUI

/// Task 10.8's "in-app guide for building Get Clipboard → Save to Kelid in
/// Shortcuts, and assigning it to Back Tap."
struct BackTapGuideView: View {
    var body: some View {
        List {
            Section {
                GuideStepView(number: 1, text: "Open the Shortcuts app and create a new shortcut.")
                GuideStepView(number: 2, text: "Add the \"Get Clipboard\" action.")
                GuideStepView(number: 3, text: "Add the \"Save to Kelid\" action (search for Kelid) and connect the clipboard text to it.")
                GuideStepView(number: 4, text: "Name the shortcut, e.g. \"Save to Kelid.\"")
            } header: {
                Text("Build the shortcut")
            }
            Section {
                GuideStepView(number: 1, text: "Open Settings → Accessibility → Touch → Back Tap.")
                GuideStepView(number: 2, text: "Choose Double Tap or Triple Tap.")
                GuideStepView(number: 3, text: "Select your \"Save to Kelid\" shortcut from the list.")
            } header: {
                Text("Assign it to Back Tap")
            } footer: {
                Text(
                    "Once set up, tapping the back of your phone copies the clipboard straight into Kelid — a two-tap capture from anywhere."
                )
            }
            Section {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .navigationTitle("Shortcuts & Back Tap")
    }
}

private struct GuideStepView: View {
    let number: Int
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "\(number).circle")
        }
    }
}
