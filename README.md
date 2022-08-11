# Obtainium

Get Android App Updates Directly From the Source.

Obtainium allows you to install and update Open-Source Apps directly from their GitHub or GitLab releases, and receive notifications when new releases are made available.

Motivation: [Side Of Burritos - You should use this instead of F-Droid | How to use app RSS feed](https://youtu.be/FFz57zNR_M0)

***Work In Progress - Currently Unusable.***

## Limitations
- App installs are assumed to have succeeded; failures and cancelled installs cannot be detected.
- Apps that are already installed are not indicated as such, since GitHub and GitLab do not provide App IDs (like `org.example.app`) to allow for comparisons.
- Auto (unattended) updates are unsupported due to a lack of any capable Flutter plugin.