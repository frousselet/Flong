# Deployment to TestFlight

A tag pushed to `origin` builds Flong on a GitHub runner and hands the result to TestFlight. Nothing is signed on the author's machine and no Apple ID is typed anywhere : the run authenticates with an App Store Connect key, which can be revoked on its own without touching the account it belongs to.

The workflow is `.github/workflows/testflight.yml`. It answers to a tag matching `v*`, which is the tag the release procedure of `CLAUDE.md` already pushes, and to a manual run from the Actions tab for anything else.

## What it does, in order

| Step | Why it is there |
| ---- | --------------- |
| picks the newest Xcode 26 on the image | the image's default is not always the newest, and Flong deploys to iOS 26 |
| `swift-format lint --strict` | the same gate as before a commit, so a tag cannot ship what a commit could not |
| unit tests on a simulator | the UI suite is skipped : it is slow, and a runner is billed by the minute |
| imports the certificate into a keychain of its own | a keychain created for the run and deleted at the end, so nothing survives it |
| archives for `generic/platform=iOS` | Release configuration, automatic signing, profiles fetched as needed |
| `-exportArchive` with `destination: upload` | the export *is* the upload : there is no `altool` step after it |
| deletes the keychain and the key | `if: always()`, so a failed run leaves nothing behind either |

## Two runs must never overlap

App Store Connect refuses a build number it has already seen, so a second run uploading the same number fails at the last step, after paying for the whole build. The workflow takes a `concurrency` group for that reason, and queues rather than cancelling : a cancelled run is a wasted one.

`CURRENT_PROJECT_VERSION` is not touched by the workflow. It moves one notch per pull request, by hand, as section *Development Guidelines* of `CLAUDE.md` requires, and `manageAppVersionAndBuildNumber` is `false` in the export options so that Xcode does not quietly renumber the build on its way out. The consequence is worth stating plainly : **a tag can be deployed once.** Re-running the workflow on the same tag uploads a number App Store Connect already holds and is refused. What follows a refused upload is a new pull request, which bumps the number, and a new tag.

## The secrets

Five, all under Settings, Secrets and variables, Actions.

| Secret | What it holds |
| ------ | ------------- |
| `ASC_KEY_ID` | the ten-character identifier of the App Store Connect key |
| `ASC_ISSUER_ID` | the issuer UUID, shown once at the top of the Keys page |
| `ASC_PRIVATE_KEY` | the contents of the `.p8` file, verbatim, header and footer included |
| `DIST_CERTIFICATE_P12` | an Apple Distribution certificate and its private key, exported as `.p12` and base64 encoded |
| `DIST_CERTIFICATE_PASSWORD` | the password given when exporting that `.p12` |

The team identifier is not a secret and is not one of them : it is already in `project.pbxproj`, and the workflow reads it back with `-showBuildSettings` rather than keeping a second copy that could drift.

**The App Store Connect key** is made at App Store Connect, Users and Access, Integrations, App Store Connect API, with the App Manager role. The `.p8` downloads once and never again, so it goes into the secret and into a password manager in the same movement.

**The certificate** is the one already in the author's login keychain if Xcode has ever distributed the application : Keychain Access, export the *Apple Distribution* entry together with its private key as a `.p12`, then `base64 -i certificate.p12 | pbcopy`. Without one, Xcode makes it under Settings, Accounts, Manage Certificates.

Nothing else is needed. Provisioning profiles are not stored anywhere : `-allowProvisioningUpdates` and the key are enough for Xcode to create and download whatever the archive asks for, which is also what keeps the workflow from breaking every time a capability is added.

## Two things that are not the workflow's doing

**The CloudKit schema has to be in production.** A TestFlight build reads and writes the production environment of `iCloud.com.rslt.Flong`, never the development one that every debug build has been using. Until the schema is deployed from the CloudKit Console, the application installs and runs and synchronizes nothing, with no error a tester would know how to report. Deploying is one button, and it is per schema change : a migration that adds a record type has to be pushed again before the build that needs it goes out.

**`aps-environment` follows the configuration.** The entitlement asked for the sandbox APNs in both configurations, which an App Store build is rejected for. It reads `$(APS_ENVIRONMENT)` now, which the target sets to `development` in Debug and `production` in Release. A debug build on a device is unaffected ; only what the runner archives changes.

## What is not there yet

**macOS.** TestFlight takes Mac applications, but the archive has to be exported as a signed `.pkg`, which needs a *3rd Party Mac Developer Installer* certificate on top of the distribution one. It is a second job of the same shape, and it is deliberately left out until that certificate exists rather than shipped as a step that fails.

**A pull request build.** Nothing verifies a branch before it is merged today. It would be the same lint and the same tests without the signing half, and it would cost what it costs : on a private repository a macOS runner is billed at ten times the minutes it spends, so a fifteen-minute run is a hundred and fifty minutes off the allowance. That is the reason the deployment workflow is one job rather than three, and the reason it does not run the UI suite.
