import SwiftUI

struct CreateSessionView: View {
    @EnvironmentObject var sessionService: SessionService
    @Environment(\.dismiss) var dismiss

    @State private var date = Date()
    @State private var time = Date()
    @State private var location = ""
    @State private var maxPlayers = 15
    @State private var priceText = ""
    @State private var defaultPriceCents: Int?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: time)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private var enteredPriceCents: Int? {
        let trimmed = priceText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let dollars = Decimal(string: trimmed) else { return nil }
        let cents = NSDecimalNumber(decimal: dollars * 100).intValue
        return cents > 0 ? cents : nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Date
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Date")
                                .font(.subheadline.bold())
                                .foregroundColor(.appTextSecondary)

                            DatePicker("", selection: $date, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.appAccentOrange)
                                .colorScheme(.dark)
                        }

                        // Time
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Time")
                                .font(.subheadline.bold())
                                .foregroundColor(.appTextSecondary)

                            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.appAccentOrange)
                                .colorScheme(.dark)
                        }

                        // Location
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location")
                                .font(.subheadline.bold())
                                .foregroundColor(.appTextSecondary)

                            TextField("e.g. Pan Pacific Park", text: $location)
                                .textFieldStyle(DarkTextFieldStyle())
                        }

                        // Max Players
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Max Players")
                                .font(.subheadline.bold())
                                .foregroundColor(.appTextSecondary)

                            HStack {
                                Button {
                                    if maxPlayers > 2 { maxPlayers -= 1 }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.appAccentOrange)
                                }

                                Text("\(maxPlayers)")
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundColor(.white)
                                    .frame(width: 50)

                                Button {
                                    maxPlayers += 1
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.appAccentOrange)
                                }
                            }
                            .padding()
                            .background(Color.appSurface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            )
                        }

                        // Price
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Price per Player ($)")
                                .font(.subheadline.bold())
                                .foregroundColor(.appTextSecondary)

                            TextField("e.g. 10", text: $priceText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(DarkTextFieldStyle())
                        }

                        // Error
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.appError)
                        }

                        // Create Button
                        Button {
                            createSession()
                        } label: {
                            HStack {
                                if isLoading {
                                    AppSpinner(color: .appBackground, size: .sm)
                                } else {
                                    Text("Create Session")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.appAccentOrange)
                            .foregroundColor(.appBackground)
                            .cornerRadius(AppStyle.buttonCornerRadius)
                        }
                        .disabled(isLoading || location.isEmpty || enteredPriceCents == nil)
                        .opacity((location.isEmpty || enteredPriceCents == nil) ? 0.6 : 1)
                    }
                    .padding(24)
                }
            }
            .condensedNavTitle("New Session")
            .task {
                await loadDefaultPrice()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.appAccentOrange)
                }
            }
        }
    }

    private func loadDefaultPrice() async {
        guard defaultPriceCents == nil else { return }
        defaultPriceCents = try? await sessionService.defaultSessionPriceCents()
        if priceText.isEmpty, let cents = defaultPriceCents {
            let dollars = Decimal(cents) / Decimal(100)
            priceText = NSDecimalNumber(decimal: dollars).stringValue
        }
    }

    private func createSession() {
        guard let priceCents = enteredPriceCents else {
            errorMessage = "Enter a valid price."
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await sessionService.createSession(
                    date: dateString,
                    time: timeString,
                    location: location,
                    maxPlayers: maxPlayers,
                    priceCents: priceCents
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Dark Text Field Style

struct DarkTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .focused($isFocused)
            .padding(14)
            .background(Color.appSurface)
            .foregroundColor(.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isFocused ? Color.appAccentOrange : Color.appBorder, lineWidth: 1)
            )
    }
}

#Preview {
    CreateSessionView()
        .environmentObject(SessionService())
}
