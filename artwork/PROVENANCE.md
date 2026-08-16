# Quick Mail artwork provenance

## octopus-setup.svg (account setup illustration)

Replaces upstream Thunderbird's octopus mascot illustration at the same
chrome path, `chrome://messenger/skin/illustrations/octopus-setup.svg`
(inside `omni.ja` at
`chrome/classic/skin/classic/messenger/illustrations/octopus-setup.svg`).
The swap happens at PACKAGING time — `packaging/build-deb.sh` repacks the
already-built `omni.ja` (entry stored uncompressed, as omni.ja requires);
no source patch, no rebuild.

Why: owner directive 2026-08-16 — in-app artwork must carry the Aura design
language, and the octopus is Thunderbird's mascot, which LICENSING.md keeps
out of Quick Mail along with the other Thunderbird marks.

- `account-setup-source.png` — original 1024x1024 render, generated
  2026-08-16 on the QuickOpen image-gen worker (Krea-2-Turbo, jobId
  img_bcf522857d7747dd), prompt: minimal flat geometric envelope +
  paper-plane line art, Aura palette (deep blue-black ground, #5b86f7
  accent), no text.
- `octopus-setup.svg` — that render with rounded corners, downscaled to
  600px and embedded as a data URI in a 300x300 SVG (the size upstream's
  SVG declares). The dark card is intentional in BOTH themes: validated on
  the Quick OS 0.1.10 VM in Aura Dark and Aura Light.

Both files are QuickOpen originals (Apache-2.0, like the rest of our layer).
Upstream's octopus artwork is MPL-2.0 and remains available in the
Thunderbird source; nothing else in omni.ja is touched, and all upstream
legal notices ship unmodified.

Other upstream illustrations at the same path (sloth.svg, form.svg,
connection-error.svg, accounts.svg, accounthub-success*.svg) are generic
non-mascot line art, appear only in transient states, and are left upstream
for now.
