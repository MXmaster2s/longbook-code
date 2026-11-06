# Apple design decisions in longbook

Apple's Human Interface Guidelines and API documentation are treated as requirements here. A
deviation needs a stated reason in the pull request.

- **Targets:** iOS 17.0 and macOS 14.0 from one SwiftUI target. An API newer than that goes behind
  `#available` with a fallback. No iPad layout yet (iPad runs the iPhone app in compatibility mode).
- **Apple's own components** over hand-made copies: the system Sign in with Apple button, Google's
  button drawn exactly to Google's branding guidelines, StoreKit views and `manageSubscriptionsSheet`, the system review prompt.
- **Copy:** professional sentence case; a field label names its field and never asks a question
  (confirmation dialogs may ask). longbook stays lowercase. No chatty fragments.
- **Colour, type, spacing** only from `packages/swift-design` tokens.
- **Both platforms:** every view change is built and looked at on iOS and macOS. Every Mac sheet closes
  with Escape (`.keyboardShortcut(.cancelAction)`); menus and keyboard shortcuts follow macOS conventions.
- **Telemetry:** a new screen, sheet, alert or button gets a telemetry name (see
  `project-structure.md`).
