# AGENTS

## Scope
These instructions apply to the entire repository.

## Project overview
- MediaHub Seedbox is a dual-node media download and preview system.
- **Download node** runs Transmission for BitTorrent, a Go (Gin) API, a Vue 3 + Vite preview wall and uses SQLite for storage.
- **Worker node** is a Python 3 script using FFmpeg to generate preview sprites and POST results back to the download node.
- All media handled by the system must be owned or properly licensed.

## Contributor guidelines
- Keep `README.md` and `SEEDBOX_SPEC.md` up to date when architecture or API behavior changes.
- Format code before committing:
  - Go: `gofmt -w`.
  - Python: `black`.
  - JavaScript/TypeScript: `prettier`.
- Run available tests:
  - Python: `pytest`.
  - Go: `go test ./...`.
  - Frontend: `npm test`.
- Use English commit messages and run the relevant formatter and test suite prior to committing.
- All HTTP requests must include `X-Auth` token as described in `SEEDBOX_SPEC.md`.

