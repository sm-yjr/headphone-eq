# Releasing

1. Update `VERSION`, the bundle build number in `script/build_and_run.sh`, visible version in Help, and `CHANGELOG.md`.
2. Run `./script/verify.sh`, inspect the diff for private data, then validate real playback and the UI. Include only original / properly licensed examples and sanitized screenshots. Do not commit `validation/`, app support files, logs, signing keys or local developer settings.
3. Set `HEADPHONE_EQ_SIGNING_IDENTITY` to a Developer ID Application identity if available. Leaving it unset produces an ad-hoc build.
4. Optionally set `HEADPHONE_EQ_NOTARY_PROFILE` to an explicitly configured, existing `notarytool` Keychain profile. Do not search or dump credentials to discover it. `script/package.sh` will submit, verify Accepted status, staple, validate and assess the app. With no profile it skips notarization; release notes **must** state this.
5. Run `./script/package.sh`. Verify the ZIP's extracted app signature, both architectures and the checksum. For notarized releases also verify the extracted app's stapled ticket and Gatekeeper assessment.
6. Commit source, tag the exact commit, and upload `HeadphoneEQ-VERSION-universal.zip` and `SHA256SUMS.txt` to a GitHub release. Mark early / unnotarized builds as previews and describe their trust status accurately. Source at that tag is the corresponding GPL source.
7. Confirm the public repository license, CI result, asset list, downloaded checksum and release link.

CI only builds ad-hoc development artifacts; signing and notarization secrets are never required for pull requests. Signing identity names may appear in app signatures; Apple-managed certificates / timestamps are public release metadata, not secrets.
