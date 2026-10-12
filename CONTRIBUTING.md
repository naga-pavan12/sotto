# Contributing to Sotto

Thanks for your interest! Sotto is MIT-licensed; by contributing you agree your
work is released under the same license. No CLA required.

## Clean-room rule

Sotto is an independent implementation. Do not paste code, model weights, or
decompiled material from any proprietary product into this repository. The
behavioural research notes in `docs/krisp-architecture.md` describe observed
behaviour only, and were used to inform our own, independent design.

## Development

- `denoiser/` — Rust static library wrapping DeepFilterNet3 (C ABI).
- `driver/` — C++ HAL audio-server plug-in (libASPL).
- `app/` — Swift menu-bar app and real-time audio engine.
- `bench/` — Python benchmark + live test harness.

Run `make test` before opening a PR. Each change should follow the existing
test-first pattern.
