import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Supabase

/// Signed-in account. Apple, Google, and email all become one Supabase user.
/// The NVIDIA key never lives here.
@MainActor
@Observable
final class AccountStore {
    private let client: SupabaseClient?

    private(set) var accessToken: String?
    private(set) var email: String?
    private(set) var appleUserID: String?

    var isSignedIn: Bool { accessToken != nil }

    init() {
        client = Self.makeClient()
        if client != nil {
            Task { await observe() }
        }
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {
        guard let client else { throw ServerError.notConfigured }
        do {
            _ = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: identityToken,
                    nonce: nonce
                )
            )
        } catch let error as ServerError {
            throw error
        } catch {
            throw ServerError.message("Couldn't sign in. Try again.")
        }
    }

    func signInWithGoogle() async throws {
        guard let client else { throw ServerError.notConfigured }
        do {
            _ = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: Self.callbackURL
            )
        } catch let error as ServerError {
            throw error
        } catch {
            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue { return }
            throw ServerError.message("Couldn't sign in. Try again.")
        }
    }

    func signIn(email: String, password: String) async throws {
        guard let client else { throw ServerError.notConfigured }
        try validate(email: email, password: password)
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch let error as ServerError {
            throw error
        } catch {
            let text = error.localizedDescription.lowercased()
            if text.contains("invalid") || text.contains("credentials") {
                throw ServerError.message("That email or password didn't match.")
            }
            throw ServerError.message("Couldn't sign in. Try again.")
        }
    }

    /// Returns true when the account was created but the person still needs to confirm their email.
    func createAccount(email: String, password: String) async throws -> Bool {
        guard let client else { throw ServerError.notConfigured }
        try validate(email: email, password: password)
        do {
            let response = try await client.auth.signUp(email: email, password: password)
            return response.session == nil
        } catch let error as ServerError {
            throw error
        } catch {
            let text = error.localizedDescription.lowercased()
            if text.contains("already") {
                throw ServerError.message("An account with this email already exists. Sign in instead.")
            }
            throw ServerError.message("Couldn't create the account. Try again.")
        }
    }

    func accessTokenForRequest() async throws -> String {
        guard let client else { throw ServerError.notConfigured }
        do {
            let session = try await client.auth.session
            accessToken = session.accessToken
            return session.accessToken
        } catch {
            throw NIMError.signedOut
        }
    }

    func signOut() async {
        try? await client?.auth.signOut()
        apply(nil)
    }

    func deleteAccount() async throws {
        guard let client else {
            await signOut()
            throw ServerError.notConfigured
        }

        do {
            try await client.rpc("delete_own_account").execute()
        } catch {
            if let url = APIConfig.endpoint("api/account"),
               let token = try? await accessTokenForRequest() {
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode), http.statusCode != 401 {
                    throw ServerError.parse(data: data, fallback: "Couldn't delete the account. Try again.")
                }
            }
        }
        await signOut()
    }

    func handle(_ url: URL) {
        client?.auth.handle(url)
    }

    /// Drops the local session when the person has disconnected the app from their Apple ID.
    func refreshCredentialState() async {
        guard let appleUserID else { return }
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleUserID)
            if state == .revoked || state == .notFound {
                try? await deleteAccount()
                await signOut()
            }
        } catch {
            // A failed check shouldn't sign anyone out.
        }
    }

    private func observe() async {
        guard let client else { return }
        for await (_, session) in client.auth.authStateChanges {
            apply(session)
        }
    }

    private func apply(_ session: Session?) {
        accessToken = session?.accessToken
        email = session?.user.email
        appleUserID = session?.user.identities?.first { $0.provider == "apple" }?.id
    }

    private func validate(email: String, password: String) throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("@") || !trimmed.contains(".") {
            throw ServerError.message("Enter an email address.")
        }
        if password.count < 6 {
            throw ServerError.message("Use at least 6 characters.")
        }
    }

    private static let callbackURL = URL(string: "youai://login-callback")

    private static func makeClient() -> SupabaseClient? {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            !urlString.contains("YOUR-PROJECT"),
            let url = URL(string: urlString),
            let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
            !key.isEmpty,
            !key.contains("YOUR-ANON-KEY")
        else { return nil }

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(auth: .init(redirectToURL: callbackURL))
        )
    }
}

enum AppleSignInNonce {
    static func random() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
