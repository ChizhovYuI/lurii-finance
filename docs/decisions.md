# Decisions

## 2026-02-28 — WebSocket scheme for EventStreamClient
- **Decision:** Use `ws://` scheme for `/api/v1/ws` instead of `http://`.
- **Why:** `URLSessionWebSocketTask` throws if the URL scheme is not `ws` or `wss`.

## 2026-02-28 — Info.plist moved to explicit file
- **Decision:** Use a custom `Info.plist` file with required bundle keys.
- **Why:** Disabling generated Info.plist caused launch failures when bundle identifier was missing.

## 2026-02-28 — Preview safety gates
- **Decision:** Skip daemon health checks, collection calls, and WebSocket connections in SwiftUI previews.
- **Why:** Preview host crashes when networking or WebSocket tasks are initiated.

## 2026-02-28 — Allocation/holdings row model
- **Decision:** Decode allocation rows into a typed `AllocationRow` model that supports `sources: [String]` and legacy `source: String`.
- **Why:** API now returns `sources` arrays; UI should join and display them consistently.

## 2026-02-28 — Dashboard auto-refresh
- **Decision:** Refresh dashboard after `collection_completed` or `snapshot_updated` events.
- **Why:** Users should see new data immediately after collection finishes.
