/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/* Quick Mail branding prefs.
 *
 * The filename is fixed by comm/mail/branding/branding-common.mozbuild
 * (ThunderbirdBranding() lists "pref/thunderbird-branding.js" literally), so it
 * keeps upstream's name even though nothing in it is upstream's any more.
 *
 * EVERY DEFAULT THAT REACHED THE NETWORK ON ITS OWN IS GONE. Quick Mail ships
 * under the OS rule "no backdoors, no dial-back, no auto-update", and the image
 * has a verified-clean egress profile (DHCP + NTP only). Two upstream defaults
 * broke that on their own, with no user action:
 *
 *   mailnews.start_page.url   loaded https://live.thunderbird.net/... in the
 *                             message pane on first run of every new profile.
 *   mail.inappnotifications   POLLED https://notifications.thunderbird.net/...
 *                             every 6 hours (mail.inappnotifications.refreshInterval
 *                             = 21600000 in all-thunderbird.js) forever.
 *
 * The remaining URLs here are user-initiated links only (clicked from menus),
 * and they point at us, not Mozilla.
 */

// ---- start page: blank, and off ------------------------------------------
// Both halves matter. Blanking the URL alone still leaves the start page
// mechanism live, and a later profile/pref merge could refill it.
pref("mailnews.start_page.enabled", false);
pref("mailnews.start_page.url", "about:blank");
pref("mailnews.start_page.override_url", "");

// ---- in-app notifications: off, and unpointed ----------------------------
// This is the periodic beacon. Disabled AND blanked for the same reason.
pref("mail.inappnotifications.enabled", false);
pref("mail.inappnotifications.url", "");

// ---- updates: there is no updater ----------------------------------------
// --disable-updater is set in mozconfig, so the app cannot update itself;
// Quick Mail updates through the AIQuick apt channel like every other Quick
// app. These are the "check for updates" menu destinations only.
pref("app.update.url.manual", "https://quickopen.ai/quick-mail");
pref("app.update.url.details", "https://quickopen.ai/quick-mail");

// ---- vendor ---------------------------------------------------------------
pref("app.vendorURL", "https://quickopen.ai/");
