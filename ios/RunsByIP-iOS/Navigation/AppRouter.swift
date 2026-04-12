import Foundation
import Combine

enum AuthState {
    case loading
    case unauthenticated
    case authenticated
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var authState: AuthState = .loading

    private var cancellables = Set<AnyCancellable>()

    func observe(authService: AuthService) {
        // React to isLoading changes
        authService.$isLoading
            .combineLatest(authService.$currentUser)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading, user in
                guard let self else { return }
                if isLoading {
                    self.authState = .loading
                } else if user != nil {
                    self.authState = .authenticated
                } else {
                    self.authState = .unauthenticated
                }
            }
            .store(in: &cancellables)
    }
}
