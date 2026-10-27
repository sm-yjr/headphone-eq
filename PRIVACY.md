# Privacy

Headphone EQ has no network client, account system, analytics SDK, crash uploader, advertising or update checker.

macOS system-audio permission is used to process the selected default output in memory. The app excludes its own output to avoid feedback. Audio buffers are not recorded to disk or sent anywhere. Pausing or quitting releases the process tap and private aggregate device.

Local files in `~/Library/Application Support/HeadphoneEQ/`:

- `presets.json`: preset names, parameters and optional author / source / notes metadata.
- `status.json`: current output display name, preset name, sample rates, processing state, frame and peak counters, clipping / invalid-sample counts, attenuation, errors and a timestamp. It contains no audio or track titles.

UserDefaults (`com.sm-yjr.headphone-eq`) stores the selected preset, consent explanation flag and an output-device UID to preset mapping. macOS unified logs include processing events and formats; device names are marked private. None of these are uploaded by the app. Presets are written atomically; an unreadable library is preserved instead of overwritten.

Export happens only when requested, through a Save dialog. A JSON export includes that preset's metadata, so review it before sharing. Screenshots and diagnostic files can reveal personal preset or device names. Remove those details before attaching them to an issue.

The app is not sandboxed because it uses Core Audio process taps. macOS permission controls still apply. It does not read microphone input, install a driver, daemon or login item, change the default audio device, or modify a headphone's internal settings.

To uninstall, quit the app and remove its bundle. You may separately remove its local data and preferences, and revoke its system-audio permission in System Settings. GitHub and Apple Music have separate privacy policies outside this app.
