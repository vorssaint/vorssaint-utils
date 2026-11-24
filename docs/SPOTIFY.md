# Spotify likes

The optional Spotify likes feature shows whether the song on the music page is
in Spotify's Liked Songs and lets you save or remove it. It does not add a library
browser or Spotify queue.

## Setup

1. Enable **Spotify likes** in Features.
2. Open **Settings → Dynamic Island → Music** and find the Spotify account setup.
3. Create an app at <https://developer.spotify.com/dashboard>, select **Web API**,
   and add exactly `http://127.0.0.1:43827/callback` as a redirect URI.
4. Paste its **Client ID** into settings and choose **Connect Spotify**.
   A client secret is not needed.
5. Approve access in the browser, then play a Spotify song and open the music page.

Spotify controls developer-app eligibility and development-mode account limits.
Follow the current dashboard requirements. Each person uses their own client ID.

## Using the heart

The heart occupies the trailing playback slot below the camera, beside Next.
While the heart is available, it replaces the audio-output button in that slot;
other players retain the output button.

A filled heart means the song is saved. A press shows an updating indicator and
waits for Spotify to accept the save or removal before changing the saved state.
Repeated presses are ignored while the request is pending.

If a request fails, a warning stays visible. Press it to retry. Network failures,
rate limits, and server errors keep the account connected. Rejected access shows
a message in settings: restore Web API access in the developer dashboard and
connect again. An expired access token gets one refresh and one retry first.
Opening the page refreshes saved state, including changes made on another device.

The integration follows the displayed recording's metadata, player, item identifier,
and playback revision. Matching prefers a Spotify URI when available; otherwise
it requires a matching title and artist and compares album names when present.
A song with insufficient metadata does not get an actionable saved-state answer.

## Account storage

Sign-in uses PKCE in the default browser with a temporary loopback listener.
Tokens are stored in an owner-only file under the app's Application Support
folder, excluded from settings backups. Disconnect removes that local account.
The client ID is a preference and participates in settings backups.

Developer and official builds have separate preferences and account storage.
Connecting one does not connect the other.

## Credits

The Spotify connection, library API integration, initial heart, settings, and
translations originate in Philip's contribution in
[PR #2750](https://github.com/vorssaint/vorssaint-utils/pull/2750). This version
adapts the heart to the current playback layout and adds confirmed updates,
persistent error feedback, reconnect handling, and request lifecycle tests.
