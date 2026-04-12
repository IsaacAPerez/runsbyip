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
    static let environment: AppEnvironment = .dev
}
