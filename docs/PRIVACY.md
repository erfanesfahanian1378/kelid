# Kelid privacy statement

**Kelid never connects to the internet.** No analytics, no crash reporting
services, no ad networks, no remote servers of any kind — not from the app,
not from the keyboard extension, not from the Share Extension. This isn't a
policy choice layered on top; the code itself contains no networking APIs
(`URLSession`, `Network.framework`, sockets) anywhere, and this is checked
automatically on every build.

## What Kelid stores, and where

Everything Kelid stores lives in a single local database, shared between the
app and the keyboard through your device's App Group storage (never
iCloud, never a server):

- **Your personal dictionary** — words and phrases you type, used to
  improve suggestions. You can view it, delete individual words, or clear
  it entirely from Dictionary → Reset personal data.
- **Clipboard history** — text and images you copy, if clipboard capture is
  enabled. You control retention, can exclude sensitive text with ignore
  patterns, and can clear it at any time.
- **Snippets** — reusable text you've saved yourself.
- **Settings** — your preferences for how the keyboard looks and behaves.

None of this is ever transmitted anywhere. It stays on your device, and
it's deleted when you delete the app.

## Full Access

iOS requires "Allow Full Access" for a custom keyboard to share data with
its own app (so your clipboard and dictionary sync between the keyboard and
Kelid's app) and to play sounds or haptics. Full Access does **not** send
your data anywhere else — it only grants Kelid's own app and keyboard
extension permission to talk to each other through the App Group. Without
it, Kelid still works for typing; it just can't sync clipboard/dictionary
data with the app or play sound/haptic feedback.

## Sensitive fields

Kelid detects password fields and secure text entry and never learns,
autocorrects from, or captures clipboard content in them.

## Backups

Backup files you create (`.kelidbackup`) are plain files you choose where
to save — Kelid never uploads them anywhere on your behalf.

## Questions

This document describes the app's actual behavior as of this build. If
anything here seems inconsistent with what you observe, please treat that
as a bug report.
