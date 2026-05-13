import Foundation
import PassKit
import StripePayments
import StripeApplePay

@MainActor
final class PaymentService: ObservableObject {
    @Published var paymentResult: PaymentResult?
    @Published var isProcessing = false

    enum PaymentResult: Equatable {
        case success
        case failed(String)
        case cancelled
    }

    /// Gate button visibility on *device capability* (has the secure element),
    /// not on *card availability*. StripeAPI.deviceSupportsApplePay() uses the
    /// stricter `canMakePayments(usingNetworks:)` check which returns false on
    /// devices with no Wallet cards configured — including Apple's review
    /// devices, which caused a 2.1 rejection ("we were unable to verify any
    /// integration of Apple Pay"). Using the no-arg canMakePayments() keeps
    /// the button visible; tapping it on a card-less device shows the system
    /// "Set Up Apple Pay" flow, which is Apple's expected behavior.
    var isApplePayAvailable: Bool {
        PKPaymentAuthorizationController.canMakePayments()
    }

    init() {
        STPAPIClient.shared.publishableKey = StripeConfig.publishableKey
    }

    func resetCheckoutState() {
        paymentResult = nil
        isProcessing = false
    }

    // MARK: - Card Payment

    func confirmPayment(
        clientSecret: String,
        paymentMethodParams: STPPaymentMethodParams,
        authenticationContext: STPAuthenticationContext
    ) async {
        paymentResult = nil
        isProcessing = true

        let intentParams = STPPaymentIntentParams(clientSecret: clientSecret)
        intentParams.paymentMethodParams = paymentMethodParams
        intentParams.returnURL = "runsbyip://stripe-redirect"

        let result = await withCheckedContinuation { continuation in
            STPPaymentHandler.shared().confirmPayment(intentParams, with: authenticationContext) { status, _, error in
                let result: PaymentResult
                switch status {
                case .succeeded:
                    result = .success
                case .canceled:
                    result = .cancelled
                case .failed:
                    result = .failed(error?.localizedDescription ?? "Payment failed. Please try again.")
                @unknown default:
                    result = .failed("Payment status was unavailable. Please try again.")
                }
                continuation.resume(returning: result)
            }
        }

        paymentResult = result
        isProcessing = false
    }

    // MARK: - Apple Pay

    func makeApplePayRequest(
        priceCents: Int,
        label: String,
        discountCents: Int = 0
    ) -> PKPaymentRequest {
        let request = StripeAPI.paymentRequest(
            withMerchantIdentifier: StripeConfig.merchantId,
            country: "US",
            currency: "USD"
        )
        // PaymentIntent amount on the server already subtracts the discount,
        // so the PassKit total must match: effective = priceCents.
        // When there's a discount, surface it as a separate negative line so
        // the user sees subtotal / discount / total in the Apple Pay sheet.
        let effective = max(priceCents, 0)
        if discountCents > 0 {
            let subtotal = effective + discountCents
            request.paymentSummaryItems = [
                PKPaymentSummaryItem(
                    label: "Subtotal",
                    amount: NSDecimalNumber(value: Double(subtotal) / 100.0)
                ),
                PKPaymentSummaryItem(
                    label: "App discount",
                    amount: NSDecimalNumber(value: -Double(discountCents) / 100.0)
                ),
                PKPaymentSummaryItem(
                    label: label,
                    amount: NSDecimalNumber(value: Double(effective) / 100.0)
                )
            ]
        } else {
            request.paymentSummaryItems = [
                PKPaymentSummaryItem(
                    label: label,
                    amount: NSDecimalNumber(value: Double(effective) / 100.0)
                )
            ]
        }
        request.requiredBillingContactFields = [.name, .emailAddress]
        return request
    }

    @discardableResult
    func confirmApplePayPayment(
        clientSecret: String,
        payment: PKPayment,
        authenticationContext: STPAuthenticationContext
    ) async -> PaymentResult {
        paymentResult = nil
        isProcessing = true

        let result: PaymentResult = await withCheckedContinuation { continuation in
            STPAPIClient.shared.createPaymentMethod(with: payment) { paymentMethod, error in
                if let error {
                    continuation.resume(returning: .failed(error.localizedDescription))
                    return
                }
                guard let paymentMethod else {
                    continuation.resume(returning: .failed("Failed to create payment method from Apple Pay."))
                    return
                }

                let intentParams = STPPaymentIntentParams(clientSecret: clientSecret)
                intentParams.paymentMethodId = paymentMethod.stripeId
                intentParams.returnURL = "runsbyip://stripe-redirect"

                STPPaymentHandler.shared().confirmPayment(intentParams, with: authenticationContext) { status, _, err in
                    switch status {
                    case .succeeded:
                        continuation.resume(returning: .success)
                    case .canceled:
                        continuation.resume(returning: .cancelled)
                    case .failed:
                        continuation.resume(returning: .failed(err?.localizedDescription ?? "Payment failed. Please try again."))
                    @unknown default:
                        continuation.resume(returning: .failed("Payment status was unavailable. Please try again."))
                    }
                }
            }
        }

        paymentResult = result
        isProcessing = false
        return result
    }
}
