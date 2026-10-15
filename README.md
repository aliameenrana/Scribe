# Scribe

A macOS app for transcribing and summarizing meeting recordings using Groq's Whisper and GPT-OSS APIs.

## Features

- Drop an audio file or record live from the mic
- Audio is chunked into 2-minute segments for more accurate transcription
- Automatic rate-limit handling with exponential backoff and resumable retries
- Segment-level transcript editing, playback, and adjustable playback speed
- Automatic summarization (short or comprehensive) after transcription
- Local history of past sessions, including audio, original and edited transcripts, and summaries

## Requirements

- macOS 13.0+
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen)
- A [Groq API key](https://console.groq.com/keys)

## Setup

```bash
xcodegen generate
open Scribe.xcodeproj
```

Build and run. On first launch, Scribe will prompt you to enter your Groq API key, which is stored locally in `~/Library/Application Support/Scribe/config.json` with owner-only file permissions. It is never bundled with the app or committed to this repo.

## Architecture

- `AudioChunker` — splits audio into fixed-length chunks via `AVAssetExportSession`
- `GroqClient` — talks to Groq's transcription and chat completion endpoints, with retry/backoff and map-reduce summarization for long transcripts
- `TranscriptionViewModel` — orchestrates chunking, transcription, and summarization
- `HistoryStore` / `Session` — persists past sessions to disk
- `PlaybackController` — audio playback with variable speed and segment-level seeking
