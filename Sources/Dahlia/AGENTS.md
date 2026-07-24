# Sources/Dahlia Application Guide

This file applies under `Sources/Dahlia/`. Changes under `Database/` must also follow `Database/AGENTS.md`.

## Architecture Invariants

Preserve the following ownership model for the recording pipeline:

```text
MicrophoneAudioCaptureSession (microphone / raw ScreenCaptureKit + AEC3 when needed)
SystemAudioCaptureManager (system audio / ScreenCaptureKit)
    ↓ onAudioBuffer
AudioSourcePipeline → CapturedAudioChunk (with session-relative timestamp)
    ↓ AudioFrameRouter
    ├─ SegmentedAudioSourceWriter (lossless, bounded immutable segments)
    └─ AudioBufferBridge → SpeechTranscriberService (low latency, at most one per source)
        ↓ TranscriptionEvent
        ↓ TranscriptionEventPipeline
        ├─ UI lane (latest preview per source; finalized backlog coalesces into reload notices)
        │   ├─ TranscriptStore (reloadable display projection, maximum 300 entries)
        │   └─ LiveCaptionStore (temporary captions during recording only)
        └─ persistence lane (finalized and translation events must not be dropped)
            ↓ TranscriptPersistenceWriter
            GRDB/SQLite (durable source of truth for finalized segments)
```

- The `RecordingSessionController` actor owns the runtime resources for capture, recognition, CAF recording, and batch scheduling.
- `CaptionViewModel` owns session requests, UI state, event projection into stores, and meeting persistence. It must not retain AVFoundation or Speech runtime resources.
- `TranscriptionEventPipeline` splits recognition events into UI and persistence lanes so MainActor rendering stalls cannot delay finalized-segment persistence.
- Summaries and exports that require the complete transcript must read SQLite off the MainActor, not the bounded `TranscriptStore`.

## Component Placement

| Layer | Primary components |
| --- | --- |
| Audio | `AudioCaptureManager`, `SystemAudioCaptureManager`, `AudioSourcePipeline`, `AudioFrameRouter`, `AudioBufferBridge` |
| Speech | `SpeechTranscriberService`, `PreviewTranslationCoordinator` |
| Models / Storage | `TranscriptStore`, `MeetingPersistenceService`, `MeetingRepository`, `AppDatabaseManager` |
| Services | `RecordingSessionController`, `SummaryService`, `VaultSyncService`, Google Calendar / Drive, exports |
| UI | `CaptionViewModel`, `SidebarViewModel`, `ContentView`, `MeetingListSidebarView`, `ControlPanelView`, `SettingsView` |

Before adding a responsibility that does not fit these ownership boundaries, inspect similar components and avoid creating a duplicate coordinator, store, or repository.

## Concurrency

- Isolate UI-exposed state, view models, stores, and repositories to `@MainActor`.
- Actors own capture, recognition, and other long-lived mutable runtimes. Do not bypass the existing `RecordingSessionController` ownership boundary.
- Avoid new `@unchecked Sendable` conformances. When an Apple framework or delegate boundary requires one, confine it to a small adapter and document the mutable-state isolation in code.
- Use `@preconcurrency import` only at import boundaries that compensate for missing Sendable conformance in Apple frameworks. Do not use it to hide application data races.

## Implementation Conventions

- Use time-sortable `UUID.v7()` values for new table-row and domain-entity IDs.
- Follow the SwiftFormat and SwiftLint configuration: four-space indentation, 150-character line limit, and trailing commas.
- Add UI strings as computed properties in `Utilities/L10n.swift`, then add the same key to both `Resources/ja.lproj` and `Resources/en.lproj`. Japanese is the primary localization.
- Settings screens use `Form` with `.formStyle(.grouped)`, `Section`, `LabeledContent`, and standard controls. Do not add custom cards, custom rows, or fixed-width control frames. Use `.toggleStyle(.switch)` for toggles and `.checkbox` for multiple selection.

## Verification

- Run tests for the changed layer first. Recording-pipeline changes must cover start, stop, reconfiguration, per-source routing, and batch-persistence boundaries as applicable.
- For UI changes, run a debug build and, when practical, inspect the affected screen in normal, empty, error, and disabled states.
