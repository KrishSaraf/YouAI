import AuthenticationServices
import SwiftUI

struct AccountSignInSection: View {
    @Environment(AccountStore.self) private var account

    @State private var email = ""
    @State private var password = ""
    @State private var rawNonce = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var notice: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            signInControls
        }
        .alert("Couldn't sign in", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var signInControls: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = AppleSignInNonce.random()
            rawNonce = nonce
            request.requestedScopes = [.email]
            request.nonce = AppleSignInNonce.sha256(nonce)
        } onCompletion: { result in
            Task { await handleApple(result) }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 44)
        .disabled(isWorking)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

        Button {
            Task { await run { try await account.signInWithGoogle() } }
        } label: {
            Text("Continue with Google")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(isWorking)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))

        TextField("Email", text: $email)
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .autocorrectionDisabled()
        SecureField("Password", text: $password)
            .textContentType(.password)

        HStack {
            Button("Sign in") {
                Task { await run { try await account.signIn(email: trimmedEmail, password: password) } }
            }
            .disabled(isWorking || trimmedEmail.isEmpty || password.isEmpty)

            Spacer()

            Button("Create account") {
                Task { await createAccount() }
            }
            .disabled(isWorking || trimmedEmail.isEmpty || password.isEmpty)
        }

        if let notice {
            Text(notice)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            errorMessage = "Couldn't sign in. Try again."
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Couldn't sign in. Try again."
                return
            }
            await run {
                try await account.signInWithApple(identityToken: token, nonce: rawNonce)
            }
        }
    }

    private func createAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let needsConfirmation = try await account.createAccount(email: trimmedEmail, password: password)
            notice = needsConfirmation ? "Check your email to finish creating the account." : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func run(_ action: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await action()
            notice = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
