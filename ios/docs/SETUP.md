# RunsByIP iOS — Setup Guide

## Prerequisites
- Xcode 15+
- iOS 17+ target
- Supabase project (existing)
- Stripe account

## 1. Configure Secrets
Open `Core/Config.swift` and fill in:
- `SupabaseConfig.url` — from Supabase dashboard > Settings > API
- `SupabaseConfig.anonKey` — from Supabase dashboard > Settings > API
- `StripeConfig.publishableKey` — from Stripe dashboard > Developers > API Keys

## 2. Run Supabase Migration
```bash
supabase db push  # or run supabase/migrations/001_ios_additions.sql in Supabase SQL editor
```

## 3. Deploy Edge Functions
```bash
supabase functions deploy send-push-notification
supabase functions deploy create-checkout  # already exists from web app
```

## 4. Configure Push Notifications (APNs)
1. In Xcode: Signing & Capabilities → + Capability → Push Notifications
2. In Apple Developer portal: create APNs key, download .p8
3. Set Supabase secrets:
```bash
supabase secrets set APNS_KEY_ID=your_key_id
supabase secrets set APNS_TEAM_ID=your_team_id
supabase secrets set APNS_BUNDLE_ID=com.yourname.runsbyip
supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"
```

## 5. Stripe iOS Setup
Add to Package.swift dependencies:
```swift
.package(url: "https://github.com/stripe/stripe-ios", from: "23.0.0")
```
In Xcode: Add `StripePaymentSheet` target to your app.

## 6. Supabase Swift SDK
```swift
.package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0")
```

## Bundle ID
Use: `com.isaacperez.runsbyip` (or your preferred ID)

## Admin Access
To make yourself admin, run in Supabase SQL editor:
```sql
UPDATE profiles SET role = 'admin' WHERE email = 'your@email.com';
```
