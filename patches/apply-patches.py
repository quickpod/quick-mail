#!/usr/bin/env python3
"""Apply Quick Mail's source patches to a pinned Thunderbird tree.

    apply-patches.py <srcdir>

House style follows quick-browser's apply-branding.py: exact-string
replacement with hard assertions, so an ESR bump that moves the code FAILS
LOUDLY here instead of silently shipping an unpatched binary. Each patch
stamps a marker so re-runs are no-ops (idempotent).

Patch 1 — OAuth client identity via prefs (owner directive 2026-08-14):
    Gmail + Microsoft OAuth2 must work for free accounts, presenting QUICK
    MAIL's own client registrations. Upstream hard-codes Mozilla's client IDs
    and its source explicitly says "Don't copy these values for your own
    application - register one for yourself!". This patch makes
    OAuth2Providers.getIssuerDetails() consult prefs first:

        quickmail.oauth.<issuer>.client_id
        quickmail.oauth.<issuer>.client_secret

    with the built-in table as fallback, so the owner's registrations can be
    shipped (and later rotated) as a prefs update through the apt channel —
    no rebuild. Until those prefs are set, the built-ins keep mail working.
"""
import sys
import pathlib

MARK = "/* quickmail-patched */"


def patch_oauth(src: pathlib.Path) -> None:
    f = src / "comm/mailnews/base/src/OAuth2Providers.sys.mjs"
    text = f.read_text()
    if MARK in text:
        print("oauth: already patched")
        return

    old = """  getIssuerDetails(issuer) {
    return kIssuers.get(issuer);
  },"""
    new = f"""  getIssuerDetails(issuer) {{
    {MARK}
    // Quick Mail: prefer OUR OAuth client registrations, delivered via prefs
    // so they can be shipped/rotated through the package channel without a
    // rebuild. Falls back to the built-in table when unset.
    const details = kIssuers.get(issuer);
    if (details?.builtIn) {{
      const branch = "quickmail.oauth." + issuer + ".";
      const clientId = Services.prefs.getStringPref(branch + "client_id", "");
      if (clientId) {{
        const clientSecret = Services.prefs.getStringPref(
          branch + "client_secret",
          ""
        );
        return {{
          ...details,
          clientId,
          clientSecret: clientSecret || details.clientSecret,
        }};
      }}
    }}
    return details;
  }},"""
    assert old in text, "OAuth2Providers.getIssuerDetails moved — repin the patch"
    f.write_text(text.replace(old, new, 1))
    print("oauth: patched (pref overlay quickmail.oauth.<issuer>.*)")


def patch_identity(src: pathlib.Path) -> None:
    """Patch 2 — product identity.

    comm/mail/moz.configure hard-codes the application identity with
    imply_option(), and an implied option CANNOT be overridden from a mozconfig:
    --with-app-name=quickmail fails configure outright with

        ConflictingOptionError: Cannot add 'MOZ_APP_NAME=thunderbird' to the
        implied set because it conflicts with --with-app-name=quickmail

    so the rebrand has to happen here. Upstream's own comment above
    MOZ_APP_BASENAME allows for it ("may vary for full rebrandings").

    What each one controls:
      MOZ_APP_NAME      the binary + install dir -> `quickmail`, never
                        `thunderbird` (trademark; see LICENSING.md).
      MOZ_APP_PROFILE   profile location -> ~/.quickmail, so Quick Mail does not
                        adopt or corrupt a real Thunderbird profile on a machine
                        that has one.
      MOZ_APP_BASENAME  application.ini "Name", Unix remoting name, Windows
                        MessageWindow. No space: it becomes a directory name and
                        an X11 remoting key, and upstream keeps it wordless
                        ("Thunderbird", "Firefox"). The spaced, user-visible
                        "Quick Mail" is MOZ_APP_DISPLAYNAME, set in
                        branding/quickmail/configure.sh.
    """
    f = src / "comm/mail/moz.configure"
    text = f.read_text()
    if MARK in text:
        print("identity: already patched")
        return

    old = '''imply_option("MOZ_APP_NAME", "thunderbird")'''
    new = f'''# {MARK} Quick Mail identity — see patches/apply-patches.py
imply_option("MOZ_APP_NAME", "quickmail")'''
    assert old in text, "MOZ_APP_NAME imply_option moved — repin the patch"
    text = text.replace(old, new, 1)

    old_prof = '''if target_is_windows or target_is_osx:
    imply_option("MOZ_APP_PROFILE", "Thunderbird")
else:
    imply_option("MOZ_APP_PROFILE", "thunderbird")'''
    new_prof = '''if target_is_windows or target_is_osx:
    imply_option("MOZ_APP_PROFILE", "QuickMail")
else:
    imply_option("MOZ_APP_PROFILE", "quickmail")'''
    assert old_prof in text, "MOZ_APP_PROFILE block moved — repin the patch"
    text = text.replace(old_prof, new_prof, 1)

    old_base = '''imply_option("MOZ_APP_BASENAME", "Thunderbird")'''
    new_base = '''imply_option("MOZ_APP_BASENAME", "QuickMail")'''
    assert old_base in text, "MOZ_APP_BASENAME imply_option moved — repin the patch"
    text = text.replace(old_base, new_base, 1)

    f.write_text(text)
    print("identity: patched (MOZ_APP_NAME/PROFILE/BASENAME -> quickmail)")


def patch_healthreport(src: pathlib.Path) -> None:
    """Patch 3 — build out the Health Report service.

    MOZ_SERVICES_HEALTHREPORT is a project_flag(), which means it can ONLY be
    set by imply_option() from the application's own moz.configure — a mozconfig
    cannot touch it:

        InvalidOptionError: MOZ_SERVICES_HEALTHREPORT= can not be set by
        mozconfig. Values are accepted from: implied

    (That is why the four `export MOZ_*` lines the mozconfig used to carry were
    removed: three were inert and this one failed configure outright.)

    Turning it off here also takes MOZ_DATA_REPORTING with it — toolkit derives
    data_reporting from health report + telemetry, so the data-reporting code is
    not compiled in at all rather than merely being switched off by a pref a
    profile could flip back. MOZ_NORMANDY is already absent for Thunderbird
    (only browser/moz.configure implies it) and MOZ_TELEMETRY_REPORTING defaults
    to mozilla_official, which an unofficial build is not.
    """
    f = src / "comm/mail/moz.configure"
    text = f.read_text()
    old = '''imply_option("MOZ_SERVICES_HEALTHREPORT", True)'''
    new = '''# Quick Mail: no data reporting compiled in (no dial-back).
imply_option("MOZ_SERVICES_HEALTHREPORT", False)'''
    if new in text:
        print("healthreport: already patched")
        return
    assert old in text, "MOZ_SERVICES_HEALTHREPORT imply_option moved — repin the patch"
    f.write_text(text.replace(old, new, 1))
    print("healthreport: patched (MOZ_SERVICES_HEALTHREPORT -> False)")


def patch_appvendor(src: pathlib.Path) -> None:
    """Patch 5 — ship OUR vendor string, not Mozilla's.

    Found by inspecting the first built package: application.ini carried
    `Vendor=Mozilla` and `quickmail --version` printed "Mozilla QuickMail",
    while LICENSING.md commits us to "own name, own icons, own vendor string"
    and to publishing nothing that suggests Mozilla produced Quick Mail. The
    binary contradicted our own trademark-compliance document.

    MOZ_APP_VENDOR is an imply_option() exactly like MOZ_SERVICES_HEALTHREPORT
    (patch 3), so a mozconfig cannot set it — `ac_add_options` /
    `export MOZ_APP_VENDOR=` are both rejected with "Values are accepted from:
    implied". It has to be patched here.

    No profile-path side effect: MOZ_APP_PROFILE is pinned to "quickmail" by
    patch 2, and nsXREDirProvider prefers MOZ_APP_PROFILE (~/.quickmail) over
    the ~/.<vendor>/<app> form, so user data stays exactly where -1 put it.
    """
    f = src / "comm/mail/moz.configure"
    text = f.read_text()
    old = '''imply_option("MOZ_APP_VENDOR", "Mozilla")'''
    new = '''# Quick Mail: our own vendor string (LICENSING.md — no endorsement).
imply_option("MOZ_APP_VENDOR", "QuickOpen")'''
    if new in text:
        print("appvendor: already patched")
        return
    assert old in text, "MOZ_APP_VENDOR imply_option moved — repin the patch"
    f.write_text(text.replace(old, new, 1))
    print("appvendor: patched (MOZ_APP_VENDOR -> QuickOpen)")


def patch_startpage(src: pathlib.Path) -> None:
    """Patch 6 — the start page shipped Thunderbird's name, logo and donation ask.

    Found by screenshotting the built app for the portal listing: the account
    central ("start") page rendered, under a heading reading "About Quick Mail":
    the Thunderbird wordmark twice, a bold "Thunderbird is funded by users like
    you!" with a link to thunderbird.net/donate, and the Thunderbird bird logo
    as a background watermark. LICENSING.md forbids exactly this — the name and
    logo are Mozilla trademarks outside the MPL grant, and soliciting donations
    for MZLA from our product is not something we may publish.

    The donation paragraph is removed rather than reworded: its <a> carries a
    hardcoded thunderbird.net/donate href in the markup, so rewording the string
    alone would leave the link behind.
    """
    ftl = src / "comm/mail/locales/en-US/messenger/accountCentral.ftl"
    text = ftl.read_text()
    new_about = (
        "about-paragraph = Quick Mail is a full-featured email and calendaring "
        "client, free for business and personal use. It is built from the "
        "Thunderbird open-source project, with telemetry and data reporting "
        "disabled at build time. It does not report to QuickOpen either."
    )
    if new_about not in text:
        old_about = [l for l in text.splitlines() if l.startswith("about-paragraph =")]
        assert old_about, "about-paragraph moved — repin the patch"
        text = text.replace(old_about[0], new_about, 1)
        # The donation message is unreferenced once the markup below is gone,
        # but a dead string still ships inside omni.ja, so neutralise it too.
        old_don = [
            l for l in text.splitlines()
            if l.startswith("about-paragraph-consider-donation =")
        ]
        assert old_don, "about-paragraph-consider-donation moved — repin the patch"
        text = text.replace(
            old_don[0],
            "about-paragraph-consider-donation = Quick Mail is free software, "
            "published by QuickOpen under the Mozilla Public License 2.0.",
            1,
        )
        ftl.write_text(text)
        print("startpage: patched (about-paragraph, donation text)")
    else:
        print("startpage: already patched")

    xhtml = src / "comm/mailnews/base/content/msgAccountCentral.xhtml"
    mk = xhtml.read_text()
    if "donationParagraph" in mk:
        start = mk.index('          <p\n            id="donationParagraph"')
        end = mk.index("</p>", start) + len("</p>\n")
        mk = mk[:start] + mk[end:]
        assert "donationParagraph" not in mk, "donation paragraph removal missed"
        assert "thunderbird.net/donate" not in mk, "donate href survived"
        xhtml.write_text(mk)
        print("startpage: donation paragraph removed from markup")
    else:
        print("startpage: donation paragraph already removed")

    # The Resources row carries the same solicitation as the Help menu:
    # thunderbird.net/participate. Support and developer docs stay (real
    # documentation for the engine); "Get Involved" goes.
    if "involvedLink" in mk:
        start = mk.index('          <a\n            id="involvedLink"')
        end = mk.index("></a>", start) + len("></a>\n")
        mk = mk[:start] + mk[end:]
        assert "involvedLink" not in mk, "involved link removal missed"
        assert "thunderbird.net/participate" not in mk, "participate href survived"
        xhtml.write_text(mk)
        print("startpage: 'Get Involved' resource link removed")
    else:
        print("startpage: 'Get Involved' already removed")

    css = src / "comm/mail/themes/shared/mail/accountCentral.css"
    ct = css.read_text()
    if "account-watermark" in ct:
        ct = ct.replace(
            '--bg-watermark: url("chrome://messenger/skin/images/account-watermark.png");',
            "--bg-watermark: none; /* Quick Mail: no Thunderbird logo */", 1)
        ct = ct.replace(
            '--bg-watermark: url("chrome://messenger/skin/images/account-watermark-light.png");',
            "--bg-watermark: none; /* Quick Mail: no Thunderbird logo */", 1)
        assert "account-watermark" not in ct, "a watermark reference survived"
        css.write_text(ct)
        print("startpage: bird watermark removed")
    else:
        print("startpage: watermark already removed")


def patch_helpmenu(src: pathlib.Path) -> None:
    """Patch 7 — drop the Help entries that solicit for Mozilla.

    Donate (thunderbird.net/donate), Get Involved (thunderbird.net/participate)
    and Feedback (connect.mozilla.org) ask OUR users to fund and contribute to
    someone else's project from inside our product. The support and
    keyboard-shortcut links are deliberately KEPT: they are genuine upstream
    documentation for the engine, and pointing at real docs implies no
    endorsement — the same line quick-browser draws around chromium.org URLs.
    """
    f = src / "comm/mail/base/content/helpMenu.inc.xhtml"
    text = f.read_text()
    if "donateURL" not in text:
        print("helpmenu: already patched")
        return
    for mid in ("getInvolved", "donationsPage", "feedbackPage"):
        start = text.index(f'<menuitem id="{mid}"')
        # each menuitem is a self-closed element ending at the first "/>"
        end = text.index("/>", start) + len("/>\n")
        line_start = text.rindex("\n", 0, start) + 1
        text = text[:line_start] + text[end:]
    for gone in ("donateURL", "getInvolvedURL", "feedbackURL"):
        assert gone not in text, f"{gone} survived the help menu patch"
    f.write_text(text)
    print("helpmenu: patched (Donate, Get Involved, Feedback removed)")


def patch_uistrings(src: pathlib.Path) -> None:
    """Patch 8 — user-visible strings that name Thunderbird as the product.

    Only strings a USER READS are touched, and only on their own key lines, so
    translator comments (the bulk of the grep hits) stay intact.

    Deliberately NOT touched, because they refer to the real Thunderbird rather
    than to us — the same rule that kept "The Chromium Authors" in the browser:
      * importDialog.ftl / aboutImport.ftl — importing a genuine Thunderbird
        profile; renaming these would make the feature lie about what it opens.
      * aboutRights.ftl — the trademark notice itself, which is accurate.
      * accountSetup.ftl — a link to the upstream FAQ, a real external resource.
      * crashreporter — not built (--disable-crashreporter).
    """
    LOCALES = src / "comm/mail/locales/en-US"
    targets = [
        (LOCALES / "chrome/overrides/appstrings.properties",
         ("confirmRepostPrompt=", "netOffline=", "networkProtocolError="),
         "Quick Mail"),
        (LOCALES / "chrome/messenger/preferences/messagestyle.properties",
         ("message3=",), "Quick Mail"),
        (LOCALES / "messenger/extensionPermissions.ftl",
         ("webext-perms-description-messagesImport =",), "{ -brand-short-name }"),
    ]
    total = 0
    for path, keys, repl in targets:
        text = path.read_text()
        out, hits = [], 0
        for line in text.splitlines(keepends=True):
            if line.startswith(keys) and "Thunderbird" in line:
                line = line.replace("Thunderbird", repl)
                hits += 1
            out.append(line)
        if not hits:
            # Already patched is not a failure — but a key that carries neither
            # the old nor the new text HAS moved, and must still fail loudly.
            done = sum(1 for l in text.splitlines()
                       if l.startswith(keys) and repl in l)
            assert done, f"no Thunderbird strings matched in {path.name} — repin"
            print(f"uistrings: {path.name} -> already patched ({done})")
            continue
        path.write_text("".join(out))
        total += hits
        print(f"uistrings: {path.name} -> {hits} string(s)")
    print(f"uistrings: {total} user-visible strings rebranded")


def patch_vendor_checksums(src: pathlib.Path) -> None:
    """Patch 4 — drop phantom files from vendored crate checksum manifests.

    The release source tarball strips `.gitmodules` out of the vendored Rust
    crates but leaves them listed in each crate's `.cargo-checksum.json`. Cargo
    then tries to hash a file that was never shipped and the whole build dies at
    the first Rust library:

        error: failed to calculate checksum of:
          comm/third_party/rust/minimal-lexical/.gitmodules
          No such file or directory (os error 2)

    This is an upstream packaging artifact, not something we caused, and it hits
    6 crates in 140.13.0esr. Rather than pin those 6 names — the set moves with
    every ESR — drop every manifest entry whose file is genuinely absent.

    Only ever REMOVES entries for missing files; a checksum that is present is
    left alone, so this cannot mask a corrupted download (fetch-source.sh has
    already verified the tarball against upstream SHA256SUMS anyway).
    """
    import json

    fixed = 0
    crates = 0
    for cs in sorted(src.glob("**/third_party/rust/*/.cargo-checksum.json")):
        try:
            data = json.loads(cs.read_text())
        except (ValueError, OSError):
            continue
        files = data.get("files")
        if not isinstance(files, dict):
            continue
        missing = [f for f in files if not (cs.parent / f).exists()]
        if not missing:
            continue
        for f in missing:
            del files[f]
            fixed += 1
        crates += 1
        cs.write_text(json.dumps(data))
        print(f"vendor: {cs.parent.name} -> dropped {', '.join(missing)}")
    if fixed:
        print(f"vendor: {fixed} phantom entries removed across {crates} crates")
    else:
        print("vendor: no phantom checksum entries")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    src = pathlib.Path(sys.argv[1])
    assert (src / "comm").is_dir(), f"not a Thunderbird tree: {src}"
    patch_oauth(src)
    patch_identity(src)
    patch_healthreport(src)
    patch_appvendor(src)
    patch_startpage(src)
    patch_helpmenu(src)
    patch_uistrings(src)
    patch_vendor_checksums(src)
    print("all patches applied")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
