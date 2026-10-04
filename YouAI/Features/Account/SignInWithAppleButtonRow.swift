import AuthenticationServices
import SwiftUI

struct SignInWithAppleButtonRow: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.colorScheme) private var colorScheme

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = []
        } onCompletion: { result in
            Task { await handle(result) }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 44)
        .disabled(isSigningIn)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .alert("Couldn't sign in", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            let code = (error as NSError).code
            if code == ASAuthorizationError.canceled.rawValue { return }
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

            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            isSigningIn = true
            defer { isSigningIn = false }
            do {
                try await account.signIn(
                    identityToken: token,
                    authorizationCode: code,
                    appleUserID: credential.user
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
