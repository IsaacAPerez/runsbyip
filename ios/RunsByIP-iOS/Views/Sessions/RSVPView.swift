import SwiftUI
import PassKit
import StripePayments
import StripeApplePay
import UIKit

struct RSVPView: View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var paymentService: PaymentService
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    let session: GameSession

    private var playerName: String {
        authService.currentProfile?.displayName ?? "Player"
    }
    private var email: String {
        authService.currentProfile?.email ?? ""
    }
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cardState = CardEntryState()
    @State private var showApplePaySheet = false
    @State private var confirmedCount = 0
    @State private var loadingMethod: String?

    private var shortDate: String {
        guard let parsed = session.parsedDate else { return session.date }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: parsed).uppercased()
    }

    private var isFormValid: Bool {
        cardState.isComplete
    }

    private var isSessionFull: Bool {
        session.isFull(using: confirmedCount)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        VStack(spacing: 4) {
                            Text(shortDate)
                                .font(.system(size: 28, weight: .black))
                                .foregroundColor(.white)

                            Text(session.time)
                                .font(.subheadline)
                                .foregroundColor(.appTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .id("top")

                        VStack(spacing: 0) {
                            SummaryRow(label: "Location", value: session.location)
                            Divider().background(Color.appBorder)
                            SummaryRow(label: "Price", value: session.priceDisplay)
                            Divider().background(Color.appBorder)
                            SummaryRow(label: "Players", value: "\(session.maxPlayers) max")
                        }

                        if isSessionFull {
                            VStack(spacing: 12) {
                                Text("Run Full")
                                    .font(.title3.bold())
                                    .foregroundColor(.white)

                                Text("All 15 spots are taken. Checkout is disabled for this run.")
                                    .font(.subheadline)
                                    .foregroundColor(.appTextSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        } else if session.paymentsOpen {
                            // Express payment methods
                            expressPaymentSection

                            paymentDivider(text: "or pay with card")

                            paymentSection
                            checkoutFooter

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }

                            Button {
                                continueToPayment()
                            } label: {
                                HStack(spacing: 10) {
                                    if isLoading || paymentService.isProcessing {
                                        ProgressView()
                                            .tint(.white)
                                            .scaleEffect(0.8)
                                    }

                                    Text(paymentService.isProcessing ? "PROCESSING PAYMENT..." : "LOCK IN SPOT — \(session.priceDisplay)")
                                        .font(.system(size: 15, weight: .black))
                                        .tracking(2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.appAccentOrange)
                                .foregroundColor(.appBackground)
                                .cornerRadius(10)
                            }
                            .disabled(isLoading || paymentService.isProcessing || !isFormValid)
                            .opacity(!isFormValid ? 0.4 : 1)
                        } else {
                            VStack(spacing: 12) {
                                Text("🔒")
                                    .font(.system(size: 44))

                                Text("Payments Drop Soon")
                                    .font(.title3.bold())
                                    .foregroundColor(.white)

                                Text("Spots open on a first-come, first-served basis. Stay ready.")
                                    .font(.subheadline)
                                    .foregroundColor(.appTextSecondary)
                                    .multilineTextAlignment(.center)

                                HStack(spacing: 8) {
                                    PulsingDot()
                                        .frame(width: 18, height: 18)
                                    Text("Waiting for drop")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.appAccentOrange)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(Color.appAccentOrange.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 999)
                                        .stroke(Color.appAccentOrange.opacity(0.2), lineWidth: 1)
                                )
                                .cornerRadius(999)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.appAccentOrange)
                }
            }
            .onChange(of: paymentService.paymentResult) { _, result in
                loadingMethod = nil
                guard let result else { return }
                switch result {
                case .success:
                    dismiss()
                case .failed(let message):
                    errorMessage = message
                case .cancelled:
                    errorMessage = "Payment was cancelled."
                }
            }
            .task {
                paymentService.resetCheckoutState()
                await refreshCapacity()
            }
            .onDisappear {
                paymentService.resetCheckoutState()
            }
        }
    }

    private var expressPaymentSection: some View {
        VStack(spacing: 10) {
            Text("EXPRESS CHECKOUT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundColor(.appTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Apple Pay
            if paymentService.isApplePayAvailable {
                if loadingMethod == "applePay" {
                    expressLoadingButton(bgColor: .white, fgColor: .black)
                } else {
                    ApplePayButton(type: .buy, style: .white) {
                        guard hasValidIdentity else { return }
                        loadingMethod = "applePay"
                        continueWithApplePay()
                    }
                    .frame(height: 48)
                    .cornerRadius(12)
                    .allowsHitTesting(loadingMethod == nil && hasValidIdentity)
                    .opacity(loadingMethod != nil && loadingMethod != "applePay" ? 0.4 : 1)
                }
            }

            // Link
            ExpressMethodButton(
                label: "Pay with Link",
                icon: "link",
                bgColor: Color(hex: "00D66F"),
                fgColor: .white,
                isLoading: loadingMethod == "link"
            ) {
                loadingMethod = "link"
                confirmWithMethod(.link)
            }
            .disabled(loadingMethod != nil || !hasValidIdentity)
            .opacity(loadingMethod != nil && loadingMethod != "link" ? 0.4 : 1)

            HStack(spacing: 10) {
                // Afterpay
                ExpressMethodButton(
                    label: "Afterpay",
                    icon: "cart.fill",
                    bgColor: Color(hex: "B2FCE4"),
                    fgColor: .black,
                    isLoading: loadingMethod == "afterpay"
                ) {
                    loadingMethod = "afterpay"
                    confirmWithMethod(.afterpayClearpay)
                }
                .disabled(loadingMethod != nil || !hasValidIdentity)
                .opacity(loadingMethod != nil && loadingMethod != "afterpay" ? 0.4 : 1)

                // Klarna
                ExpressMethodButton(
                    label: "Klarna",
                    icon: "k.circle.fill",
                    bgColor: Color(hex: "FFB3C7"),
                    fgColor: .black,
                    isLoading: loadingMethod == "klarna"
                ) {
                    loadingMethod = "klarna"
                    confirmWithMethod(.klarna)
                }
                .disabled(loadingMethod != nil || !hasValidIdentity)
                .opacity(loadingMethod != nil && loadingMethod != "klarna" ? 0.4 : 1)
            }
        }
    }

    private func expressLoadingButton(bgColor: Color, fgColor: Color) -> some View {
        HStack {
            ProgressView().tint(fgColor).scaleEffect(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var hasValidIdentity: Bool {
        !playerName.isEmpty && !email.isEmpty
    }

    private func paymentDivider(text: String) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 1)
            Text(text)
                .font(.caption)
                .foregroundColor(.appTextSecondary)
                .layoutPriority(1)
            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 1)
        }
    }

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PAYMENT")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundColor(.appTextSecondary)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.appAccentOrange.opacity(0.14))
                            .frame(width: 44, height: 44)

                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.appAccentOrange)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Secure card entry")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Card details stay inside Stripe’s PCI-compliant fields, but the full checkout experience stays inside Runs.")
                            .font(.subheadline)
                            .foregroundColor(.appTextSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Card details")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)

                    CardField(cardState: $cardState)
                }

                HStack(spacing: 12) {
                    PaymentPill(icon: "bolt.fill", label: "Instant confirmation")
                    PaymentPill(icon: "creditcard.fill", label: "Visa • Amex • Mastercard")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.appSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        )
        .cornerRadius(16)
    }

    private var checkoutFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TOTAL")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(.appTextSecondary)

                Spacer()

                Text(session.priceDisplay)
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(.white)
            }

            Text("You’ll secure one player spot for this run. If 3D Secure is required, Stripe may briefly show its authentication screen before dropping you back into the app.")
                .font(.caption)
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.appSurfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        )
        .cornerRadius(16)
    }

    private func continueWithApplePay() {
        guard hasValidIdentity else { return }
        guard !isSessionFull else {
            errorMessage = "This run is full. Checkout is no longer available."
            return
        }

        isLoading = true
        errorMessage = nil
        paymentService.resetCheckoutState()

        let paymentRequest = paymentService.makeApplePayRequest(
            priceCents: session.priceCents,
            label: "RunsByIP — \(session.location)"
        )
        let authContext = PaymentAuthenticationContext()

        Task {
            do {
                let clientSecret = try await sessionService.createCheckout(
                    sessionId: session.id,
                    playerName: playerName,
                    playerEmail: email
                )

                // Present Apple Pay sheet
                guard let controller = PKPaymentAuthorizationViewController(paymentRequest: paymentRequest) else {
                    errorMessage = "Apple Pay is not available on this device."
                    isLoading = false
                    return
                }

                let delegate = ApplePayDelegate { payment in
                    Task {
                        await paymentService.confirmApplePayPayment(
                            clientSecret: clientSecret,
                            payment: payment,
                            authenticationContext: authContext
                        )
                    }
                }

                controller.delegate = delegate
                objc_setAssociatedObject(controller, "applePayDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)

                if let topVC = authContext.authenticationPresentingViewController() as? UIViewController {
                    topVC.present(controller, animated: true)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            loadingMethod = nil
        }
    }

    private func continueToPayment() {
        guard isFormValid else { return }
        guard !isSessionFull else {
            errorMessage = "This run is full. Checkout is no longer available."
            return
        }

        isLoading = true
        errorMessage = nil
        paymentService.resetCheckoutState()

        let paymentMethodParams = cardState.makePaymentMethodParams(name: playerName, email: email)
        let authContext = PaymentAuthenticationContext()

        Task {
            do {
                let clientSecret = try await sessionService.createCheckout(
                    sessionId: session.id,
                    playerName: playerName,
                    playerEmail: email
                )

                await paymentService.confirmPayment(
                    clientSecret: clientSecret,
                    paymentMethodParams: paymentMethodParams,
                    authenticationContext: authContext
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func confirmWithMethod(_ type: STPPaymentMethodType) {
        guard hasValidIdentity, !isSessionFull else {
            if isSessionFull { errorMessage = "This run is full." }
            return
        }

        isLoading = true
        errorMessage = nil
        paymentService.resetCheckoutState()

        let billingDetails = STPPaymentMethodBillingDetails()
        billingDetails.name = playerName
        billingDetails.email = email

        let params = STPPaymentMethodParams()
        params.billingDetails = billingDetails
        switch type {
        case .link:
            params.type = .link
            params.link = STPPaymentMethodLinkParams()
        case .afterpayClearpay:
            params.type = .afterpayClearpay
            params.afterpayClearpay = STPPaymentMethodAfterpayClearpayParams()
        case .klarna:
            params.type = .klarna
            params.klarna = STPPaymentMethodKlarnaParams()
        default:
            isLoading = false
            loadingMethod = nil
            return
        }

        let authContext = PaymentAuthenticationContext()

        Task {
            do {
                let clientSecret = try await sessionService.createCheckout(
                    sessionId: session.id,
                    playerName: playerName,
                    playerEmail: email
                )

                await paymentService.confirmPayment(
                    clientSecret: clientSecret,
                    paymentMethodParams: params,
                    authenticationContext: authContext
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            loadingMethod = nil
        }
    }

    private func refreshCapacity() async {
        do {
            confirmedCount = try await sessionService.fetchRSVPCount(for: session.id)
            if isSessionFull {
                errorMessage = "This run is full. Checkout is no longer available."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CardField: View {
    @Binding var cardState: CardEntryState
    @FocusState private var focusedField: Field?

    private enum Field {
        case number
        case expiration
        case cvc
    }

    var body: some View {
        VStack(spacing: 12) {
            PaymentInputField(
                title: "Card number",
                text: Binding(
                    get: { cardState.formattedCardNumber },
                    set: { cardState.updateCardNumber($0) }
                ),
                placeholder: "1234 1234 1234 1234",
                keyboardType: .numberPad,
                textContentType: .creditCardNumber,
                isValid: cardState.cardNumberValidationState == .valid,
                isInvalid: cardState.showsCardNumberError,
                errorText: cardState.cardNumberError
            )
            .focused($focusedField, equals: .number)
            .submitLabel(.next)
            .onSubmit { focusedField = .expiration }

            HStack(spacing: 12) {
                PaymentInputField(
                    title: "Exp.",
                    text: Binding(
                        get: { cardState.formattedExpiration },
                        set: { cardState.updateExpiration($0) }
                    ),
                    placeholder: "MM/YY",
                    keyboardType: .numberPad,
                    isValid: cardState.expirationValidationState == .valid,
                    isInvalid: cardState.showsExpirationError,
                    errorText: cardState.expirationError
                )
                .focused($focusedField, equals: .expiration)
                .submitLabel(.next)
                .onSubmit { focusedField = .cvc }

                PaymentInputField(
                    title: "CVC",
                    text: Binding(
                        get: { cardState.cvc },
                        set: { cardState.updateCVC($0) }
                    ),
                    placeholder: cardState.cvcPlaceholder,
                    keyboardType: .numberPad,
                    isValid: cardState.cvcValidationState == .valid,
                    isInvalid: cardState.showsCVCError,
                    errorText: cardState.cvcError
                )
                .focused($focusedField, equals: .cvc)
                .submitLabel(.done)
            }
        }
    }
}

private struct CardEntryState {
    var cardNumber = ""
    var expirationMonth = ""
    var expirationYear = ""
    var cvc = ""

    var cardBrand: STPCardBrand {
        STPCardValidator.brand(forNumber: cardNumber)
    }

    var cvcPlaceholder: String {
        cardBrand == .amex ? "4 digits" : "3 digits"
    }

    var formattedCardNumber: String {
        cardNumber.chunked(every: 4).joined(separator: " ")
    }

    var formattedExpiration: String {
        switch (expirationMonth.isEmpty, expirationYear.isEmpty) {
        case (true, true):
            return ""
        case (false, true):
            return expirationMonth
        default:
            return "\(expirationMonth)/\(expirationYear)"
        }
    }

    var cardNumberValidationState: STPCardValidationState {
        STPCardValidator.validationState(forNumber: cardNumber, validatingCardBrand: true)
    }

    var expirationValidationState: STPCardValidationState {
        guard !expirationMonth.isEmpty, !normalizedExpirationYear.isEmpty else {
            return .incomplete
        }

        return STPCardValidator.validationState(
            forExpirationYear: normalizedExpirationYear,
            inMonth: expirationMonth
        )
    }

    var cvcValidationState: STPCardValidationState {
        STPCardValidator.validationState(forCVC: cvc, cardBrand: cardBrand)
    }

    var isComplete: Bool {
        cardNumberValidationState == .valid && expirationValidationState == .valid && cvcValidationState == .valid
    }

    var cardNumberError: String? {
        showsCardNumberError ? "Enter a valid card number." : nil
    }

    var expirationError: String? {
        showsExpirationError ? "Enter a valid expiration date." : nil
    }

    var cvcError: String? {
        showsCVCError ? "Enter a valid CVC." : nil
    }

    var showsCardNumberError: Bool {
        !cardNumber.isEmpty && cardNumberValidationState == .invalid
    }

    var showsExpirationError: Bool {
        (!expirationMonth.isEmpty || !expirationYear.isEmpty) && expirationValidationState == .invalid
    }

    var showsCVCError: Bool {
        !cvc.isEmpty && cvcValidationState == .invalid
    }

    private var normalizedExpirationYear: String {
        guard !expirationYear.isEmpty else { return "" }
        if expirationYear.count == 4 { return expirationYear }

        let currentYearPrefix = String(Calendar.current.component(.year, from: Date())).prefix(2)
        return currentYearPrefix + expirationYear
    }

    mutating func updateCardNumber(_ value: String) {
        cardNumber = value.filter(\.isNumber).prefix(19).string
    }

    mutating func updateExpiration(_ value: String) {
        let digits = value.filter(\.isNumber).prefix(4).string
        expirationMonth = String(digits.prefix(2))
        expirationYear = digits.count > 2 ? String(digits.dropFirst(2)) : ""
    }

    mutating func updateCVC(_ value: String) {
        let maxLength = cardBrand == .amex ? 4 : 3
        cvc = value.filter(\.isNumber).prefix(maxLength).string
    }

    func makePaymentMethodParams(name: String, email: String) -> STPPaymentMethodParams {
        let billingDetails = STPPaymentMethodBillingDetails()
        billingDetails.name = name
        billingDetails.email = email

        let cardParams = STPPaymentMethodCardParams()
        cardParams.number = cardNumber
        cardParams.expMonth = NSNumber(value: UInt(expirationMonth) ?? 0)
        cardParams.expYear = NSNumber(value: UInt(normalizedExpirationYear) ?? 0)
        cardParams.cvc = cvc

        return STPPaymentMethodParams(card: cardParams, billingDetails: billingDetails, metadata: nil)
    }
}

private struct PaymentInputField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let keyboardType: UIKeyboardType
    var textContentType: UITextContentType? = nil
    let isValid: Bool
    let isInvalid: Bool
    let errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundColor(.appTextSecondary)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.appSurfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .cornerRadius(14)

            if let errorText, isInvalid {
                Text(errorText)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }

    private var borderColor: Color {
        if isInvalid {
            return .red.opacity(0.8)
        }

        if isValid {
            return .appAccentOrange.opacity(0.9)
        }

        return .appBorder
    }
}

private final class PaymentAuthenticationContext: NSObject, STPAuthenticationContext {
    nonisolated func authenticationPresentingViewController() -> UIViewController {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .first(where: \.isKeyWindow)?
                    .rootViewController?.topMostViewController ?? UIViewController()
            }
        }

        return DispatchQueue.main.sync {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController?.topMostViewController ?? UIViewController()
        }
    }
}

private extension UIViewController {
    var topMostViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostViewController
        }

        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.topMostViewController ?? navigationController
        }

        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.topMostViewController ?? tabBarController
        }

        return self
    }
}

private class ApplePayDelegate: NSObject, PKPaymentAuthorizationViewControllerDelegate {
    private let onPayment: (PKPayment) -> Void

    init(onPayment: @escaping (PKPayment) -> Void) {
        self.onPayment = onPayment
    }

    func paymentAuthorizationViewController(
        _ controller: PKPaymentAuthorizationViewController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        onPayment(payment)
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
    }

    func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        controller.dismiss(animated: true)
    }
}

private struct ApplePayButton: UIViewRepresentable {
    let type: PKPaymentButtonType
    let style: PKPaymentButtonStyle
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: type, paymentButtonStyle: style)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {
        context.coordinator.action = action
    }

    class Coordinator {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

private struct PaymentPill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: Capsule())
    }
}

private struct ExpressMethodButton: View {
    let label: String
    let icon: String
    let bgColor: Color
    let fgColor: Color
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(fgColor).scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                    Text(label)
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(bgColor)
            .foregroundColor(fgColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct PulsingDot: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 18, height: 18))
        container.backgroundColor = .clear

        let pulseLayer = CALayer()
        pulseLayer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        pulseLayer.position = CGPoint(x: 9, y: 9)
        pulseLayer.cornerRadius = 5
        pulseLayer.backgroundColor = UIColor(Color.appAccentOrange).withAlphaComponent(0.4).cgColor
        container.layer.addSublayer(pulseLayer)

        let dotLayer = CALayer()
        dotLayer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        dotLayer.position = CGPoint(x: 9, y: 9)
        dotLayer.cornerRadius = 5
        dotLayer.backgroundColor = UIColor(Color.appAccentOrange).cgColor
        container.layer.addSublayer(dotLayer)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.8
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.75
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.2
        group.repeatCount = .infinity
        pulseLayer.add(group, forKey: "pulse")

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.appTextSecondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.vertical, 12)
    }
}

private extension String {
    func chunked(every size: Int) -> [String] {
        guard size > 0 else { return [self] }

        var chunks: [String] = []
        var start = startIndex

        while start < endIndex {
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[start..<end]))
            start = end
        }

        return chunks
    }
}

private extension Substring {
    var string: String { String(self) }
}

#Preview {
    RSVPView(session: GameSession(
        id: "1",
        date: "2026-03-28",
        time: "6:00 PM",
        location: "Pan Pacific Park",
        priceCents: 1000,
        minPlayers: 10,
        maxPlayers: 15,
        status: "open",
        paymentsOpen: false,
        createdAt: ""
    ))
    .environmentObject(SessionService())
    .environmentObject(PaymentService())
    .environmentObject(AuthService())
}
