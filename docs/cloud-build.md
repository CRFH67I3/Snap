# Cloud build (GitHub Actions)

The IPA is built on a GitHub-hosted macOS runner. Nothing is built locally.

## How to run

Two ways to start a build:

1. Push to `main` (changes under `Snap/`, `project.yml` or the workflow file).
2. In the repository, open **Actions → Build iOS IPA → Run workflow**.

When the run finishes, the IPA is available in two places:

- **Workflow run artifact** `Snap-IPA-<run number>` (kept for 30 days).
- **GitHub Release** `build-<run number>` with the IPA attached (not created for pull requests).

## Signing modes

### Unsigned IPA (default)

If no signing secrets are configured, the workflow produces `Snap-unsigned.ipa`.
It is a valid IPA archive, but it is not code-signed and must be re-signed with
a tool such as AltStore or Sideloadly before installation.

### Signed IPA

Add these repository secrets (**Settings → Secrets and variables → Actions**) to
get a signed, installable IPA:

| Secret | Purpose |
| --- | --- |
| `SIGNING_CERTIFICATE_P12_BASE64` | Base64 of a `.p12` certificate (Apple Development / Distribution) |
| `SIGNING_CERTIFICATE_PASSWORD` | Password for the `.p12` |
| `PROVISIONING_PROFILE_BASE64` | Base64 of the provisioning profile for `com.tao.Snap` |
| `DEVELOPMENT_TEAM` | Apple Developer Team ID |
| `PROVISIONING_PROFILE_SPECIFIER` | Profile name used in the export options (recommended) |

Export a certificate from Keychain Access as `.p12`, convert it with
`base64 -i cert.p12 | tr -d '\n'`, and store the result as the secret.
Do the same for the `.mobileprovision` file. The profile must match the
bundle ID `com.tao.Snap` and the export method chosen when starting the workflow
(`development`, `ad-hoc`, or `app-store`).

For `ad-hoc` and `app-store` distribution, ensure the certificate type and
profile type match; otherwise `xcodebuild -exportArchive` will fail with a
signing error.

## Troubleshooting

- **Build fails at `xcodegen generate`**: check `project.yml`. The workflow
  installs XcodeGen via Homebrew automatically.
- **Export fails with a signing error**: verify the certificate, profile,
  team ID, and export method all match.
- **No artifact**: inspect the failed step log in the Actions run.
