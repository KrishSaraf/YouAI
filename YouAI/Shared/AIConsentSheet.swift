import SwiftUI

/// Asked once, before the first photo or spoken log leaves the phone for the AI service.
struct AIConsentSheet: View {
    var onAnswer: (Bool) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text("Photos you choose to estimate, of a meal or gym equipment.")
                    } icon: {
                        Image(systemName: "camera")
                    }
                    Label {
                        Text("The text of what you said when you log by voice. The recording stays on your iPhone.")
                    } icon: {
                        Image(systemName: "text.bubble")
                    }
                } header: {
                    Text("What's sent")
                }

                Section {
                    Text("Lean Lah!'s server passes it to OpenRouter, which runs Google's Gemini model to make the estimate. Their own privacy policies apply. Lean Lah! doesn't keep what's sent for the estimate and never uses it for ads. If you save a meal, a small copy of its photo is saved with it on your account.")
                } header: {
                    Text("Who it goes to")
                }

                Section {
                    Text("Estimates can be wrong. Check them before you save. They aren't medical or dietary advice.")
                } footer: {
                    Text("Nothing is sent until you tap Allow. You can turn this off in Settings.")
                }
            }
            .navigationTitle("AI estimates")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        onAnswer(true)
                    } label: {
                        Text("Allow")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)

                    Button("Not now") { onAnswer(false) }
                }
                .padding()
                .background(.bar)
            }
        }
        .interactiveDismissDisabled()
    }
}

/// Runs an AI request once the person has agreed, asking first if they haven't.
struct AIConsentGate: ViewModifier {
    @Binding var pending: (() -> Void)?
    @Environment(AppSettings.self) private var settings

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        )) {
            AIConsentSheet { allowed in
                let action = pending
                pending = nil
                if allowed {
                    settings.allowsAISharing = true
                    action?()
                }
            }
        }
    }
}

extension View {
    func aiConsentGate(_ pending: Binding<(() -> Void)?>) -> some View {
        modifier(AIConsentGate(pending: pending))
    }
}
