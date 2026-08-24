# ImagePeek Release Procedure

## 1. Build an unsigned review archive

Run this locally for internal review only:

```zsh
./scripts/package-release.sh
```

The archive is written to `artifacts/ImagePeek-1.0.0-unsigned.zip`. The script refuses to overwrite an existing archive.

## 2. Prepare Apple distribution credentials

Before public distribution, install a `Developer ID Application` certificate in Keychain Access. Create a notarization profile locally; do not put credentials in this repository:

```zsh
xcrun notarytool store-credentials "ImagePeekNotary"
```

Apple will ask for the account information interactively. The resulting profile stays in the local keychain.

## 3. Sign and notarize

After the certificate and Keychain profile are available, run:

```zsh
./scripts/sign-and-notarize-release.sh \
  "Developer ID Application: Your Name (TEAMID)" \
  "ImagePeekNotary" \
  "./artifacts"
```

The script signs with hardened runtime, submits an intermediate ZIP for notarization, staples the app ticket, validates it with Gatekeeper, and then writes the final distributable `artifacts/ImagePeek-1.0.0.zip`. The intermediate submission archive remains beside it for auditability.

## 4. Install test

On a Mac that has not previously run the app, unzip the signed archive, move `ImagePeek.app` to `/Applications`, launch it, grant Accessibility, and verify a WPS and Excel preview.
