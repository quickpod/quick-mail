# Quick Mail — licensing verdict

**Verdict: ALLOWED, with mandatory rebrand.** Quick Mail is built from the
Thunderbird source tree (mozilla-central + comm-central), which is licensed
under the **Mozilla Public License 2.0** — the same license family as the
Quick Office engine (LibreOffice, MPL-2.0). Decided 2026-08-14, following the
precedent recorded in `repos/quickoffice-engine/LICENSING.md` and
`repos/quick-browser/LICENSING.md`.

## What the MPL-2.0 permits

- **Commercial use, modification, redistribution** — explicitly allowed.
  Every major Thunderbird derivative (Betterbird, various enterprise builds)
  exists on exactly this basis.
- **File-level copyleft only.** Modifications to MPL-covered *files* must stay
  MPL and their source must be available when we distribute executables
  (MPL-2.0 §3.2). We discharge this the same way Quick Office does: this
  repository is public and carries the exact recipe — pin, patches, branding,
  build configuration — that produces the shipped binary. Larger works and
  our own new files are not captured.

## What is NOT permitted — and how we comply

- **"Thunderbird" and its logo are Mozilla trademarks.** They are not part of
  the MPL grant, exactly as "Chrome"/"Firefox" branding is separate from the
  code. The official branding lives behind `MOZ_OFFICIAL_BRANDING`; we never
  enable it. Quick Mail builds with its **own branding directory**
  (`branding/quickmail` → `comm/mail/branding/quickmail`): own name, own
  icons, own vendor string.
- **No endorsement.** Nothing we publish may suggest Mozilla or MZLA
  Technologies produced or endorses Quick Mail. The About dialog, the portal
  listing and the package description all carry the line: *"Built from the
  Thunderbird open-source project. Not Thunderbird, and neither produced nor
  endorsed by Mozilla or MZLA Technologies."*

## Attribution we ship

- Per-file MPL license headers are left untouched (rewriting them would breach
  MPL §3.4).
- `licenses/MPL-2.0.txt` ships in every package, plus `NOTICE` naming the
  upstream project and where its source lives.
- The in-app About/credits page stays reachable.

## Version policy

Pinned to the **ESR line** (`pin.txt`), currently 140.13.0esr: same standing
obligation as Quick Browser — an email client handles untrusted remote content,
Mozilla ships ESR security releases on a regular cadence, and a fork that lags
is an unpatched client, not a private one. Bumping `pin.txt` is routine
maintenance, not a project.
