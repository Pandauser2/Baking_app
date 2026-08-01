import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var authManager: AuthManager

    @State private var email = ""
    @State private var password = ""
    @State private var mode: AuthMode = .signIn
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                if case .failure(let configError) = environment.configResult {
                    Section("Configuration") {
                        Text(configurationMessage(configError))
                            .foregroundStyle(.red)
                    }
                }

                Section("Credentials") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    SecureField("Password", text: $password)
                    if mode == .signUp {
                        Text(SignupPasswordRules.tooShortMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Mode") {
                    Picker("Auth Mode", selection: $mode) {
                        ForEach(AuthMode.allCases, id: \.self) { authMode in
                            Text(authMode.title).tag(authMode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(mode.actionTitle)
                        }
                    }
                    .disabled(!canSubmit || isSubmitting)
                }

                if case .error(let message) = authManager.status {
                    Section("Error") {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Welcome")
        }
    }

    private var canSubmit: Bool {
        guard !email.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp {
            return SignupPasswordRules.validationErrorMessage(for: password) == nil
        }
        return true
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        switch mode {
        case .signIn:
            await authManager.signIn(email: email, password: password)
            if case .signedIn = authManager.status {
                environment.analytics.track(.loginCompleted)
            }
        case .signUp:
            await authManager.signUp(email: email, password: password)
            if case .signedIn = authManager.status {
                environment.analytics.track(.signupCompleted)
            }
        }
    }

    private func configurationMessage(_ error: AppConfigError) -> String {
        switch error {
        case .missingValue:
            return "Missing configuration values. Add Config.local.xcconfig and GoogleService-Info.plist."
        case .invalidURL:
            return "SUPABASE_URL is invalid in configuration."
        }
    }
}

private enum AuthMode: CaseIterable {
    case signIn
    case signUp

    var title: String {
        switch self {
        case .signIn: return "Sign In"
        case .signUp: return "Sign Up"
        }
    }

    var actionTitle: String {
        switch self {
        case .signIn: return "Sign In"
        case .signUp: return "Create Account"
        }
    }
}

