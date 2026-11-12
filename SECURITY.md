# Security

## Report a problem

Use GitHub's private report: the **Security** tab of this repository, then **Report a vulnerability**. Do not open a public issue for a security problem.

## What PadTube does

- It connects only to Google's servers (YouTube, its image and video hosts, and Google's sign-in service). It has no server of its own, no analytics and no ads SDK.
- It uses its own TLS client (OpenSSL 3.5.9, TLS 1.2 and 1.3) and checks certificates against the root certificates in the app, because old iOS versions have old root stores.
- A local HLS server on **127.0.0.1** feeds iOS's player. It does not listen on the network.
- A release contains no key and no credential. `scripts/check_release.py` and gitleaks check this before each release.

## What it stores on the iPad

| Data | Where |
|------|-------|
| Sign-in token (OAuth refresh and access token of the YouTube TV sign-in) | The app's SQLite database in its own folder. Not in the Keychain, and not encrypted by PadTube |
| History, searches, settings | The same database |

Sign out on the Account screen to delete the tokens. Deleting the app deletes the database.

## Known limits

| Limit | Detail |
|-------|--------|
| Token on a jailbroken iPad | Other code with root can read the app's folder, and so the sign-in token. Use the sign-in only on an iPad that you trust. You can remove PadTube's access in your Google Account, under security, third-party connections |
| Sign-in client | PadTube signs in as YouTube's TV app (the code flow at google.com/device). It reads the TV app's public client ID from YouTube at run time; the repository contains none |
| Old iOS | Apple sends iOS 6 to 12 few or no security fixes. Do not use this iPad for other private work |
| Sideloaded builds | A sideload tool signs the app with your Apple Account. Get the tool from its own site |
| Device testing | Only an iPad mini 1 on iOS 6.1.3 has run the app |
