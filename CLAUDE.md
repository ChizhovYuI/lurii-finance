# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

This is a macOS SwiftUI app built with Xcode. Use the MCP xcode-tools for all operations:

- **Build**: `BuildProject` MCP tool (or Cmd+B in Xcode)
- **Run tests**: `RunAllTests` / `RunSomeTests` MCP tools
- **Quick validation**: `XcodeRefreshCodeIssuesInFile` for fast per-file diagnostics without a full build
- **Preview rendering**: `RenderPreview` MCP tool to verify UI changes
- **Code snippets**: `ExecuteSnippet` to test logic in context of a file

Use `context7` MCP to look up latest Apple framework documentation (SwiftUI, Foundation, etc.) when implementing new features.

## Architecture

**macOS SwiftUI app** connecting to a local daemon at `http://127.0.0.1:19274`.

### Navigation
`RootView` switches between `LoginView` (disconnected) and `MainShellView` (connected). `MainShellView` uses `NavigationSplitView` with sidebar sections defined in `AppState.AppSection`.

### State Management
- **AppState**: `@MainActor` singleton injected as `@EnvironmentObject`. Holds connection status, collection progress, web sync statuses, UI state (selectedSection, hideBalance, globalSearchQuery).
- **Feature ViewModels**: `@StateObject` per feature screen, each with `@Published` properties. Use `async/await` for API calls.
- **No Combine for new code** — prefer Swift async/await.

### Networking
- **APIClient**: Singleton REST client. JSON with snake_case decoding. All methods are `async throws`.
- **APIEndpoints**: Enum with static path constants.
- **APIModels**: All DTOs. Codable structs with `CodingKeys` for snake_case mapping.
- **EventStreamClient**: WebSocket (`URLSessionWebSocketTask`) for real-time events (collection, commentary, snapshot, updates). Reconnects with exponential backoff.

### Web Sync
Browser-based sync for providers (MEXC, EMCD). `WebSyncCoordinator` manages daily auto-sync. `WebSyncProvider` enum defines login URLs and cookie domains.

### Design System
- **DesignTokens**: Centralized colors, spacing, typography, corner radii.
- **Glass-morphism UI**: `.glassEffect()`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`, `GlassEffectContainer`.
- **Custom window**: Transparent titlebar, NSVisualEffectView background.

## Code Conventions

- **@MainActor** on all ViewModels and state classes
- **PascalCase** types, **camelCase** properties/methods
- 4-space indentation
- `@State private var` for view-local state, `@AppStorage` for persisted preferences
- Feature views use `.toolbar {}` for actions (search, filters, page controls)
- Popovers/sheets via `@State` binding + `.sheet(item:)` or `.popover(isPresented:)`
- Tables use `.fixedSize(horizontal: true, vertical: false)` + `.frame(maxWidth: .infinity)` pattern for content-dependent width with centering
- Preview guards: `ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"`

## Project Layout

```
lurii-finance/lurii-finance/
├── App/            # AppState, MainShellView, RootView, Notifications
├── Core/
│   ├── Networking/ # APIClient, APIEndpoints, APIModels
│   ├── Theme/      # DesignTokens, AppTheme
│   ├── WebSync/    # Browser-based provider sync
│   └── WS/         # EventStreamClient (WebSocket)
├── Features/       # MVVM feature modules (Dashboard, Transactions, Sources, etc.)
└── SharedUI/       # Reusable components (StatCard, EmptyStateView, Formatters)
```

Each feature folder contains `*View.swift` + `*ViewModel.swift`, with optional sheets/popovers.
