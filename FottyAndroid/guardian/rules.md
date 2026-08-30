# Code Guardian: Directives & Standards

This document defines the rules and standards the Guardian uses to evaluate the codebase.

## 0. Sports Integrity (CRITICAL)
- **Sports-Only**: Fotty is a sports-exclusive platform. Any reference to movies, TV shows, seasons (episodic), episodes, watchlists, or cinema-style libraries is PROHIBITED.
- **Authorized Sources**: Only use approved, legal streaming sources. Flag any unauthorized or suspicious scrapers.
- **Data Fidelity**: Prioritize fixtures, standings, and match-day metrics.

## 1. Safety First
- **No Direct Mutation**: The Guardian in Phase 1 must NEVER modify source code.
- **Privacy**: Never log or report secrets, API keys, or personal data.
- **Reversibility**: Recommendations should favor small, isolated changes over broad refactors.

## 2. Architecture: Clean & Reactive
- **Unidirectional Data Flow (UDF)**: UI -> ViewModel (State/Intent) -> Repository.
- **Repository Pattern**: No UI component or ViewModel should call Retrofit/OkHttp directly.
- **Hilt/Dagger**: Use constructor injection. Avoid `EntryPoint` unless strictly necessary.

## 3. UI: Jetpack Compose & Material 3
- **Stability**: Prefer `@Immutable` or `@Stable` for UI state models.
- **Performance**: Avoid expensive calculations in `@Composable` scopes; use `remember` or `derivedStateOf`.
- **M3 Standards**: Strictly follow Material 3 color tokens and typography. No hardcoded colors.
- **Previews**: Every UI component should have a `@Preview`.

## 4. Kotlin & Logic
- **Null Safety**: Avoid `!!`. Use `?.let`, `?:`, or explicit null checks.
- **Concurrency**: Use `viewModelScope` for UI-related tasks and `Dispatchers.IO` for network/disk.
- **Naming**: Follow industry standards (PascalCase for classes, camelCase for variables).

## 5. Official References (Trusted Sources)
- [Android Developer Guides](https://developer.android.com/docs)
- [Kotlin Documentation](https://kotlinlang.org/docs/home.html)
- [Compose Performance](https://developer.android.com/jetpack/compose/performance)
- [Material 3 Design Guidelines](https://m3.material.io/)
- [Security Best Practices](https://developer.android.com/topic/security/best-practices)
