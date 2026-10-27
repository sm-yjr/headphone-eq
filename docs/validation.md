# Validation record — 0.3.0 preview

This record separates numerical tests, application observations and untested hardware. No personal preset tables, device UIDs, audio recordings or raw local status files are published.

## Automated verification

`./script/verify.sh` passed on Apple-silicon macOS with Swift 6.4 Command Line Tools:

- JSON and supported APO text round trips; disabled filters and comments.
- Rejection of malformed / unsupported directives, duplicate numbers, overflowing IDs, non-finite parameters, excessive filters, excessive file size and duplicate library IDs.
- Known peak / shelf reference gains and conservative headroom, including a 20 Hz high-Q shelf and a 20 kHz high-Q peak.
- Actual processed sine-wave gain against analytical filter response, at 30 / 100 / 1000 / 3000 / 12000 Hz, for original generic presets and a synthetic three-filter fixture, at 44.1 / 48 / 96 kHz.
- Silent right-channel isolation, planar input to interleaved output in the real C callback, rapid parameter updates, retained-preamp reference mode, −30 dB attenuation and restoration.
- Finite output from non-finite input, invalid-input counting, final sample clamping and clipped-sample counting.

Universal release builds contain arm64 and x86_64. Bundle metadata and the Developer ID code signature are verified. Intel execution is not tested on physical Intel hardware.

## Application observations

On the development Mac's physical headphone output at 48 kHz:

- The app launched paused and loaded the existing personal library without bundling that data.
- Playback frames advanced; input, processing and hardware rates were all 48 kHz. Digital peaks changed as expected during original/EQ and temporary attenuation transitions. The diagnostic returned automatically after 10 seconds; clipping and invalid-sample counts remained zero during the observed session.
- Actual controls were exercised for preset selection, original/EQ shortcuts, start/pause, text import and numeric parameter editing. Import preserved all three filters of an original generic fixture.
- Native JSON export completed through the system Save sheet; the file was read back and all three filter values matched the original fixture. Serialization is also covered by numerical tests. The app provides copy-to-clipboard export.

Earlier private development builds were audibly checked by the owner on HD600 via the headphone jack and WH-1000XM4 via Bluetooth. Those observations support the underlying route design, **not** a new acoustic validation of this public version. The preview has not been measured with a calibrated ear simulator.

## Visual evidence

`docs/preview.png` is an **offscreen render of the actual SwiftUI view**, using original generic presets and a synthetic output label. It is not a desktop screenshot or proof of live playback. It was inspected for chart, sidebar, editor and footer layout. The debug-only renderer does not capture the desktop, read a personal library or start audio. Native controls were also checked through accessibility observations. A full-resolution screenshot of the live window was unavailable in the automation environment.

To reproduce the render after a debug build:

```sh
HEADPHONE_EQ_RENDER_PREVIEW="$PWD/docs/preview.png" .build/debug/HeadphoneEQ
```

## Limits

Physical Intel execution, minimum supported macOS 14.4, exhaustive sleep / hot-plug combinations, AirPlay, HDMI multi-channel, aggregate outputs, exclusive-mode players, protected content and arbitrary third-party devices have not been certified. The app stops on detected device / sample-rate changes rather than silently adapting. No claim of acoustic THD improvement, resonance removal, headphone safety certification or perceptual loudness matching is made.

The official preview is Developer ID signed but **not Apple notarized**. CI artifacts are ad-hoc development builds. Review the release notes and signature status before installing.
