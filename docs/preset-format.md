# Preset formats

Import accepts one UTF-8 APO parameter preset or one Headphone EQ JSON object, up to 1 MiB. A library JSON is not a single-preset import. Maximum: 16 uniquely numbered filters, 200 presets per library. IDs are integers 0–9999. Names are 1–120 characters; frequency 20–20000 Hz; gain −18…+18 dB; Q 0.1…20; requested preamp −60…0 dB. All numeric values must be finite.

APO supports decimal-dot numbers, `#` comments, `Preamp: value dB`, and `Filter N: ON|OFF PK|PEQ|LSC|HSC Fc value Hz Gain value dB Q value`. Duplicate Preamp or filter numbers, unknown directives and unsupported shelf forms are errors. This deliberately limited parser does not execute configuration directives or load additional files. `LSC` and `HSC` use Q with RBJ biquad coefficients.

A JSON export preserves the UUID and optional provenance *values*; these keys must be present (they can contain empty strings). Import assigns a fresh UUID so it never overwrites an existing preset. This example is an original generic tone adjustment:

```json
{
  "id": "535B4570-880A-4E12-B331-1227A8D12345",
  "name": "My gentle shelf",
  "author": "",
  "sourceURL": "",
  "notes": "Original generic example",
  "preamp": -3,
  "bands": [
    {"id": 1, "kind": "lowShelf", "frequency": 90, "gain": 2, "q": 0.71, "enabled": true}
  ]
}
```

Kinds: `peak`, `lowShelf`, `highShelf`. An APO export retains the requested preamp and filters, but not JSON metadata. Other equalizers may not apply Headphone EQ's automatic headroom, so independently check their preamp and clipping behavior. Headphone EQ's output headroom is computed for the actual processing sample rate, with a 0.8 dB margin; very extreme curves requiring attenuation below −60 dB stop processing.
