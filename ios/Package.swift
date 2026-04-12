// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RunsByIP-iOS",
    platforms: [
        .iOS(.v17)
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0"),
        .package(url: "https://github.com/stripe/stripe-ios", from: "23.0.0"),
    ],
    targets: [
        .target(
            name: "RunsByIP-iOS",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "StripePayments", package: "stripe-ios"),
                .product(name: "StripeApplePay", package: "stripe-ios"),
            ],
            path: "RunsByIP-iOS"
        ),
    ]
)
