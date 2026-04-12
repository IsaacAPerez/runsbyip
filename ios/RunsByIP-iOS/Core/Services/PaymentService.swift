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

    var isApplePayAvailable: Bool {
        StripeAPI.deviceSupportsApplePay()
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

    func makeApplePayRequest(priceCents: Int, label: String) -> PKPaymentRequest {
        let request = StripeAPI.paymentRequest(
            withMerchantIdentifier: StripeConfig.merchantId,
            country: "US",
            currency: "USD"
        )
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: label,
                amount: NSDecimalNumber(value: Double(priceCents) / 100.0)
            )
        ]
        request.requiredBillingContactFields = [.name, .emailAddress]
        return request
    }

    func confirmApplePayPayment(
        clientSecret: String,
        payment: PKPayment,
        authenticationContext: STPAuthenticationContext
    ) async {
        paymentResult = nil
        isProcessing = true

        let paymentMethodParams = STPPaymentMethodParams(card: STPPaymentMethodCardParams(), billingDetails: nil, metadata: nil)

        // Create payment method from Apple Pay token
        let applePayParams = STPPaymentMethodCardParams()
        let intentParams = STPPaymentIntentParams(clientSecret: clientSecret)
        intentParams.paymentMethodParams = STPPaymentMethodParams(card: applePayParams, billingDetails: nil, metadata: nil)

        // Use the Stripe Apple Pay token approach
        STPAPIClient.shared.createPaymentMethod(with: payment) { [weak self] paymentMethod, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.paymentResult = .failed(error.localizedDescription)
                    self.isProcessing = false
                    return
                }

                guard let paymentMethod else {
                    self.paymentResult = .failed("Failed to create payment method from Apple Pay.")
                    self.isProcessing = false
                    return
                }

                let intentParams = STPPaymentIntentParams(clientSecret: clientSecret)
                intentParams.paymentMethodId = paymentMethod.stripeId
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

                self.paymentResult = result
                self.isProcessing = false
            }
        }
    }
}
