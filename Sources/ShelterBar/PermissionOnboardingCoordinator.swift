import ShelterBarCore

@MainActor
final class PermissionOnboardingCoordinator {
    private var onboarding = PermissionOnboarding()
    private var accessibilityObserver: Task<Void, Never>?
    private let accessibilityGranted: () -> Bool
    private let screenCaptureGranted: () -> Bool
    private let requestAccessibilityHandler: () -> Void
    private let requestScreenCaptureHandler: () -> Void

    init(
        accessibilityGranted: @escaping () -> Bool,
        screenCaptureGranted: @escaping () -> Bool,
        requestAccessibility: @escaping () -> Void,
        requestScreenCapture: @escaping () -> Void
    ) {
        self.accessibilityGranted = accessibilityGranted
        self.screenCaptureGranted = screenCaptureGranted
        requestAccessibilityHandler = requestAccessibility
        requestScreenCaptureHandler = requestScreenCapture
    }

    @discardableResult
    func advance() -> PermissionOnboardingAction? {
        advance(accessibilityGranted: accessibilityGranted())
    }

    private func advance(accessibilityGranted hasAccessibility: Bool) -> PermissionOnboardingAction? {
        if hasAccessibility { stopObservingAccessibility() }
        let action = onboarding.nextAction(
            accessibilityGranted: hasAccessibility,
            screenCaptureGranted: hasAccessibility && screenCaptureGranted()
        )
        switch action {
        case .requestAccessibility:
            requestAccessibilityHandler()
            observeAccessibilityGrant()
        case .requestScreenCapture:
            requestScreenCaptureHandler()
        case nil:
            break
        }
        return action
    }

    func requestAccessibility() {
        onboarding.record(.requestAccessibility)
        requestAccessibilityHandler()
        observeAccessibilityGrant()
    }

    func requestScreenCapture() {
        onboarding.record(.requestScreenCapture)
        stopObservingAccessibility()
        requestScreenCaptureHandler()
    }

    func stopObservingAccessibility() {
        accessibilityObserver?.cancel()
        accessibilityObserver = nil
    }

    private func observeAccessibilityGrant() {
        guard accessibilityObserver == nil else { return }
        // The shelf can close when System Settings takes focus.
        accessibilityObserver = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                guard self.accessibilityGranted() else { continue }
                _ = self.advance(accessibilityGranted: true)
                return
            }
        }
    }
}
