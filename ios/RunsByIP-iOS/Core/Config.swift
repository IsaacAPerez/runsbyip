import Foundation

enum AppEnvironment {
    case dev
    case prod
}

struct SupabaseConfig {
    static let url = URL(string: "https://ncjgkthruvapcogqaxhi.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5jamdrdGhydXZhcGNvZ3FheGhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM2NDMxODQsImV4cCI6MjA4OTIxOTE4NH0.68aoboLH1-iqLZCszeAKwuThqELKf4Ymt_U0mAbZxNI"
}

struct StripeConfig {
    static let publishableKey = "pk_live_51TBVnZJ5QuONgvx1wFyjaN9bZOMTgYXqW6xuSsg8J0yX5FPfmQR1x9VHBFPGkVoSmDv4PEzrxMhDcMoBA5Vj8epu00jp5l3oBQ"
    static let merchantId = "merchant.com.isaacperez.runsbyip"
}

struct AppConfig {
    static let environment: AppEnvironment = .prod
}

// MARK: - Chat write gate (send, typing indicator, reactions)

struct ChatWriteGateConfig {
    /// Passphrase is stored as a bcrypt hash in Supabase (`chat_write_gate` + `verify_chat_write_gate` RPC).
    /// Apply migration `009_chat_write_gate.sql`, then rotate with:
    /// `UPDATE chat_write_gate SET password_hash = extensions.crypt('secret', extensions.gen_salt('bf')) WHERE id = 1;`

    /// Set to `false` to allow all signed-in users to use chat without a passphrase.
    static let isEnabled = true
}
