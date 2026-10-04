import AuthenticationServices
import Foundation
import Observation

/// Sign in with Apple session. The NVIDIA key never lives here.
@MainActor
@Observable
final class AccountStore {
    private enum Account {
        static let session = "session-token"
        static let appleUser = "apple-user-id"
    }

    private(set) var sessionToken: String?
    private(set) var appleUserID: String?

    var isSignedIn: Bool { sessionToken != nil }

    init() {
        sessionToken = KeychainStore.get(Account.session)
        appleUserID = KeychainStore.get(Account.appleUser)
    }

    func signIn(identityToken: String, authorizationCode: String?, appleUserID: String) async throws {
        guard let url = APIConfig.endpoint("api/session") else { throw ServerError.notConfigured }

        var body: [String: Any] = ["identity_token": identityToken]
        if let authorizationCode, !authorizationCode.isEmpty {
            body["authorization_code"] = authorizationCode
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServerError.message("Couldn't sign in. Try again.") }
        guard (200..<300).contains(http.statusCode) else {
            throw ServerError.parse(data: data, fallback: "Couldn't sign in. Try again.")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["token"] as? String,
            !token.isEmpty
        else { throw ServerError.message("Couldn't sign in. Try again.") }

        KeychainStore.set(token, for: Account.session)
        KeychainStore.set(appleUserID, for: Account.appleUser)
        sessionToken = token
        self.appleUserID = appleUserID
    }

    func deleteAccount() async throws {
        guard let sessionToken else {
            signOut()
            return
        }
        guard let url = APIConfig.endpoint("api/account") else { throw ServerError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 {
                signOut()
                return
            }
            throw ServerError.parse(data: data, fallback: "Couldn't delete the account. Try again.")
        }
        signOut()
    }

    /// Drops the local session when the person has disconnected the app from their Apple ID.
    func refreshCredentialState() async {
        guard let appleUserID else { return }
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleUserID)
            if state == .revoked || state == .notFound {
                try? await deleteAccount()
                signOut()
            }
        } catch {
            // A failed check shouldn't sign anyone out.
        }
    }

    private func signOut() {
        KeychainStore.set(nil, for: Account.session)
        KeychainStore.set(nil, for: Account.appleUser)
        sessionToken = nil
        appleUserID = nil
    }
}
