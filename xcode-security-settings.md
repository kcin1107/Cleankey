# Xcode Security Settings

Security build-setting decisions for Cleankey.

## Enabled settings

- `ENABLE_HARDENED_RUNTIME = YES`: Required for Developer ID notarization.
- `ENABLE_ENHANCED_SECURITY = YES`: Enables Xcode 27 compiler and runtime hardening for the shipping app.
- `com.apple.security.hardened-process = true`: Enables hardened-process runtime protections.
- `com.apple.security.hardened-process.enhanced-security-version-string = 2`: Selects version 2 protections.
- `com.apple.security.hardened-process.hardened-heap = true`: Enables heap type isolation.
- `com.apple.security.hardened-process.dyld-ro = true`: Protects dynamic-loader state as read-only.
- `com.apple.security.hardened-process.platform-restrictions-string = 2`: Enables dynamic-loader and Mach-message platform restrictions.
- `ENABLE_POINTER_AUTHENTICATION = NO` on `CleankeyTests`: The hosted test bundle must consume the app's standard arm64 Swift module. The shipping app retains pointer authentication.

## Disabled settings

None.

## Deferred

- Hardware memory tagging: Requires supported hardware and a soft-mode field-report rollout. Do not introduce it immediately before a release.
- Checked pointer arithmetic: Not applicable to this macOS target.
- Additional Clang diagnostics and bounds safety: Not applicable to this pure-Swift project.
