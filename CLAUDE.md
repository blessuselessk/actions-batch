# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

`actions-batch` is a Go CLI that turns GitHub Actions into a time-sharing compute platform. It creates a temporary GitHub repo, writes a workflow + user script into it, monitors execution, streams logs, downloads artifacts, then optionally deletes the repo.

## Build & Test Commands

```bash
make build          # go build
make test           # unit tests (CGO_ENABLED=0)
make e2e            # e2e tests (--tags e2e), hits GitHub API
make gofmt          # format check (fails on diff)
make dist           # cross-compile: linux/darwin/windows × amd64/arm64/armhf
make all            # gofmt + test + build + dist + hash
```

## Architecture

Single-binary CLI, no subcommands — everything runs from `main.go`:

1. **Parse flags** → read token + script file → generate random repo name
2. **Create temp GitHub repo** → push workflow YAML (`templates/workflow.yaml`) + user script (`job.sh`)
3. **Inject secrets** (`secrets.go`) — reads files from `--secrets-from` dir, encrypts with NaCL box, creates GitHub repo secrets. Filenames become `UPPER_SNAKE_CASE` env vars.
4. **Poll for completion** — watches workflow run status at `--interval` (default 1s) up to `--max-attempts` (default 360)
5. **Stream logs** — downloads + extracts workflow logs zip, filters out GitHub system steps
6. **Download artifacts** — if job wrote to `./uploads/`, artifacts are downloaded to `--out` dir
7. **Cleanup** — deletes the temp repo (unless `--delete=false`)

Key files:
- `main.go` — orchestration, CLI flags, GitHub API interactions
- `secrets.go` — NaCL encryption for GitHub Actions secrets
- `unzip.go` — log/artifact zip extraction
- `templates/render.go` + `templates/workflow.yaml` — Go text/template workflow generation
- `pkg/version.go` — build-time version injection via ldflags

## Version Injection

```
-X github.com/alexellis/actions-batch/pkg.Version=...
-X github.com/alexellis/actions-batch/pkg.GitCommit=...
```

Set via `LDFLAGS` in the Makefile, used in `make dist`. Plain `make build` does not inject version info.

## Go Module

Module path: `github.com/alexellis/actions-batch` (Go 1.20). Key deps: `go-github/v57`, `golang.org/x/oauth2`, `golang.org/x/crypto` (NaCL box).
