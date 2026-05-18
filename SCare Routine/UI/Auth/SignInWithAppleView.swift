import SwiftUI
import AuthenticationServices

/// Apple Sign In butonu + akış sarmalayıcısı.
/// `onSuccess` ile başarılı login sonrası dönen user'ı parent'a iletir.
struct SignInWithAppleView: View {
    let locale: String
    var onSuccess: (AuthUser) -> Void
    var onError: (APIError) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isLoading = false

    var body: some View {
        ZStack {
            SignInWithAppleButton(.signIn,
                onRequest: configureRequest,
                onCompletion: handleCompletion
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .cornerRadius(12)
            .disabled(isLoading)
            .opacity(isLoading ? 0.5 : 1)

            if isLoading {
                ProgressView()
            }
        }
    }

    // MARK: - Apple request konfigürasyonu

    private func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        // İsteğe bağlı: nonce ekleyebilirsek replay attack'a karşı koruma artar.
        // Şimdilik backend identityToken'ı Apple JWKS ile doğruluyor — yeterli.
    }

    // MARK: - Tamamlanma callback

    private func handleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                onError(.invalidResponse)
                return
            }
            isLoading = true
            Task {
                do {
                    let user = try await AuthService.shared.signInWithApple(
                        credential: credential, locale: locale
                    )
                    await MainActor.run {
                        isLoading = false
                        onSuccess(user)
                    }
                } catch let apiError as APIError {
                    await MainActor.run {
                        isLoading = false
                        onError(apiError)
                    }
                } catch {
                    await MainActor.run {
                        isLoading = false
                        onError(.requestFailed(error))
                    }
                }
            }

        case .failure(let error):
            // Kullanıcı iptal ettiyse sessiz dön
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                return
            }
            onError(.requestFailed(error))
        }
    }
}

#Preview {
    SignInWithAppleView(
        locale: "tr",
        onSuccess: { _ in },
        onError: { _ in }
    )
    .padding()
}
