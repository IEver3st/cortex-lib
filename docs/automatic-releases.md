# Automatic releases

Commit your changes and push to `main`. GitHub Actions runs the source checks and Lua specs, assigns the next version, validates a runtime ZIP, and publishes it on GitHub Releases. A failed check blocks publication. Feature branches do not publish; pull requests to `main` run validation.

Customers can always download the current package here:

**[Download cortex-lib.zip](https://github.com/IEver3st/cortex-lib/releases/latest/download/cortex-lib.zip)**

Extract it as `cortex-lib` and start it before its consumers. Release assets also include `cortex-lib.zip.sha256`. Use the attached ZIP; GitHub's generic source archives contain developer files.

## Versions

No manual version bump or tag is needed. If the manifest version is already used, the workflow increments the highest stable release tag's patch number. If you set a higher version in `fxmanifest.lua`, such as `3.0.0`, it uses that version instead. Keep the README version badge consistent when editing the manifest yourself.

The release tag points to a commit derived from the pushed source, with the manifest and README badge set to the release version. The source SHA appears in that commit's `Source-commit` trailer. The bot does not push version commits back to `main`, so it does not create extra pull/rebase work. The manifest on `main` is the requested minimum version; the manifest in the release is the actual published version.

Rerunning the same source reuses its tag. Published assets are never replaced. Interrupted draft uploads can be retried using Actions' **Re-run failed jobs**. Push runs are serialized; GitHub may replace an older pending run with a newer push while a release is running.

## Maintenance and checks

Put `[skip release]` in the final commit message of a push to run validation and packaging without publishing. The initial automation setup uses this to avoid publishing the older committed snapshot while local library work is pending.

For a manual dry run, open **Actions > Release > Run workflow**, choose `main`, and leave **Publish a release after validation** unchecked. Check it to publish the current committed source after validation. The run summary records the candidate version, source SHA, and ZIP checksum.

Before pushing gameplay or NUI changes to `main`, complete their in-game acceptance checks. CI cannot verify FiveM or CEF. For a library update, install the generated archive on a test server, restart `cortex-lib` before consumers, check startup/F8 logs, and exercise the changed UI or API and resource-stop cleanup. Keep experiments on a branch until ready for customers.

This public repository uses standard GitHub-hosted Ubuntu runners, which are [free for public repositories](https://docs.github.com/en/actions/concepts/billing-and-usage). Publication uses GitHub's built-in token with write permission only in the release job. No Worker, paid hosting, personal token secret, or external build service is required.
