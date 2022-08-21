# Obtainium

Get Android App Updates Directly From the Source.

Obtainium allows you to install and update Open-Source Apps directly from their releases pages, and receive notifications when new releases are made available.

Currently supported App sources:
- GitHub

Motivation: [Side Of Burritos - You should use this instead of F-Droid | How to use app RSS feed](https://youtu.be/FFz57zNR_M0)

***Work In Progress - Far from ready.***

## Limitations
- App installs are assumed to have succeeded; failures and cancelled installs cannot be detected.
- Already installed apps are not detected, for the above reason along with the fact that App sources do not provide App IDs (like `org.example.app`) to allow for comparisons.
- Auto (unattended) updates are unsupported due to a lack of any capable Flutter plugin.