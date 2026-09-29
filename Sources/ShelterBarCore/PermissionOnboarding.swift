public enum PermissionOnboardingAction: Equatable, Sendable {
    case requestAccessibility
    case requestScreenCapture
}

public struct PermissionOnboarding: Sendable {
    private var handledAccessibility = false
    private var handledScreenCapture = false

    public init() {}

    public mutating func nextAction(
        accessibilityGranted: Bool,
        screenCaptureGranted: Bool
    ) -> PermissionOnboardingAction? {
        if accessibilityGranted { handledAccessibility = true }
        if screenCaptureGranted { handledScreenCapture = true }

        if !accessibilityGranted {
            guard !handledAccessibility else { return nil }
            handledAccessibility = true
            return .requestAccessibility
        }

        if !screenCaptureGranted {
            guard !handledScreenCapture else { return nil }
            handledScreenCapture = true
            return .requestScreenCapture
        }

        return nil
    }

    public mutating func record(_ action: PermissionOnboardingAction) {
        switch action {
        case .requestAccessibility:
            handledAccessibility = true
        case .requestScreenCapture:
            handledScreenCapture = true
        }
    }
}
