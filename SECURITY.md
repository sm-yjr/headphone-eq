# Security

Only the latest preview receives fixes. This is an early desktop audio tool; review source and release signatures before installing.

Report ordinary bugs through Issues. For vulnerabilities, use GitHub's private vulnerability reporting option if available, or open a minimal issue requesting a private channel without publishing exploit details, secrets or personal audio data. Do not upload credentials or your entire preset library.

Preset import is size limited and accepts data only. It does not execute scripts, follow source URLs, include other files or interpret arbitrary APO commands. Invalid files are rejected. The app runs without App Sandbox to use process taps; permissions are provided by macOS. Revoke system-audio permission or quit the app to stop capture.

Official ZIP previews may be Developer ID signed but unnotarized; release notes state the exact trust status. Ad-hoc CI artifacts are development builds and are not official notarized releases. This project never recommends disabling Gatekeeper, SIP or other system protections.
