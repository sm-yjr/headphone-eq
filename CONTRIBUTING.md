# Contributing

Small, focused pull requests are welcome. Describe the user-visible problem, proposed behavior and how you verified it. Contributions are made under GPL-3.0-only; do not add third-party presets, code, images or datasets without compatible redistribution rights and attribution. No contributor license assignment is required.

Use Swift 6+ and macOS 14.4+. Run `./script/verify.sh` and `./script/build_and_run.sh --build-only`. Changes to realtime code must keep allocation, locks, logging and file access outside the callback. Verify new filter behavior numerically across sample rates. UI changes should include a current screenshot without personal preset data.

For audio changes, also test a physical output: real playback, original/EQ switching, the temporary attenuation check, pause/quit and output disconnection. Record what was actually tested; digital counters are not acoustic measurements. Do not change system volume or another application's settings automatically.

Keep scope small. Do not introduce automatic playback, network requests, uploaders or a login item as incidental changes. Please discuss broad architecture changes in an issue first. Respectful, specific feedback is expected.
