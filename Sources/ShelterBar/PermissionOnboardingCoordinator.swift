import ShelterBarCore

@MainActor
final class PermissionOnboardingCoordinator {
    private var onboarding = PermissionOnboarding()
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
        let action = onboarding.nextAction(
            accessibilityGranted: accessibilityGranted(),
            screenCaptureGranted: screenCaptureGranted()
        )
        guard let action else { return nil }
        perform(action)
        return action
    }

    func requestAccessibility() {
        onboarding.record(.requestAccessibility)
        requestAccessibilityHandler()
    }

    func requestScreenCapture() {
        onboarding.record(.requestScreenCapture)
        requestScreenCaptureHandler()
    }

    private func perform(_ action: PermissionOnboardingAction) {
        switch action {
        case .requestAccessibility:
            requestAccessibilityHandler()
        case .requestScreenCapture:
            requestScreenCaptureHandler()
        }
    }
}
