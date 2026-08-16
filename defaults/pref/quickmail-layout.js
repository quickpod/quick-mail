/* Quick Mail — modern layout defaults.
 *
 * Installed to <appdir>/defaults/pref/ by packaging/build-deb.sh; every .js
 * here is read as DEFAULT prefs at startup, so these are defaults, not locks:
 * View > Layout and the density/appearance settings still work and win.
 *
 * The target look (owner directive 2026-08-16) is a leading modern client —
 * new Outlook / Apple Mail: folder pane left, CARDS message list in the
 * middle, vertical reading pane on the right, prominent compose top-left,
 * search top-center. Thunderbird 140's Supernova UI is exactly that when
 * these three prefs hold, and 140 already defaults to them — they are pinned
 * here so the shipped layout no longer depends on upstream defaults drifting,
 * and so the intent is on the record next to the values.
 *
 * Value semantics verified against the pinned 140.13.0esr source:
 *   mail.pane_config.dynamic       2 = vertical view
 *                                  (all-thunderbird.js; 0 classic, 1 wide)
 *   mail.threadpane.listview       0 = cards, 1 = table
 *                                  (about3Pane.js updateThreadView)
 *   mail.threadpane.cardsview.rowcount  3-row cards: sender / subject /
 *                                  snippet (clamped 2..3 in about3Pane.js)
 *   mail.uidensity                 1 = default density (0 compact, 2 touch)
 *
 * Validated live on the Quick OS 0.1.10 VM in Aura Dark and Aura Light,
 * including a theme flip with the app open (re-themes live, no restart).
 */

pref("mail.pane_config.dynamic", 2);
pref("mail.threadpane.listview", 0);
pref("mail.threadpane.cardsview.rowcount", 3);
pref("mail.uidensity", 1);
