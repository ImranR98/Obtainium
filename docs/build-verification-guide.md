# Build verification in ObtainX

ObtainX has two security-focused checks that can help you decide whether an update is safer to install:

- **F-Droid / Izzy build verification** checks whether the APK is known to match a build made from published source code.
- **GitHub build verification** checks whether a GitHub release APK has GitHub attestation proof for that exact downloaded file.

These checks do **not** tell you whether an app is safe or free of malware. They answer one narrower question:

> Can ObtainX find independent proof that this exact file is the one the developer actually built from the source code?

When an app can offer that proof and the download matches, you have a little more confidence that nobody swapped in a tampered file along the way. When the proof is missing, doesn't match, or can't be reached, ObtainX tells you that too, so you can decide for yourself.

---

## At a glance

| | F-Droid / Izzy | GitHub |
|---|---|---|
| What it proves | The download matches an APK rebuilt from the app's public source code. | GitHub has matching signed proof for this exact file. |
| Where to turn it on | **Enforce build verification** toggle (per app). | **GitHub Build Verification** mode: Off / Audit Only / Enforce (per app). |
| Needs a GitHub token | No. | Yes — a validated token under **Settings → Source-specific**. |
| Can show a "mismatch"? | Yes — **Mismatched Build**. | No — it can only tell whether proof exists, not whether proof conflicts. |
| When warning badges appear | Only when **Enforce** is on. | In **Audit Only** and **Enforce** (not **Off**). |
| Can block an install? | Yes, when **Enforce** is on. | Yes, when **Enforce** is selected. |

---

## The result badges

You see these badges on the app's detail page, in the **Security** row of the **Version** card.

| Badge | Plain meaning | Should you install? |
|---|---|---|
| **Verified Build** | ObtainX found verification proof for this build. (Green check = reproducible build; blue shield = GitHub attestation.) | This is the best result from these checks. It still does not guarantee the app is harmless. |
| **Mismatched Build** | F-Droid / Izzy verification data says this APK does not match the expected reproducible build result. | Treat this as a strong warning. Install only if you understand why it mismatched. |
| **Unverified Build** | GitHub did not provide attestation proof for this exact APK file. | This does not prove tampering. It means ObtainX could not find GitHub proof for that file. |
| **No Verification Data** | The source was checked, but it does not publish verification data for this app or build. | Common for many apps. It means there is nothing for ObtainX to verify. |
| **Can't Check** | ObtainX tried to check, but the check failed because of a network error, rate limit, API problem, missing digest, or similar issue. | Try again later, check your token/settings, or install only if you trust the source without this proof. |

> **Note:** Both checks use the same **Verified Build** label, but they are different proofs. The reproducible-build badge is a green check; the GitHub attestation badge is a blue shield.

---

## Feature 1: F-Droid and Izzy build verification

### What it means

Some F-Droid-style repositories can publish information proving that an APK matches a build made from the app's source code.

In plain language:

> The app source code was built again, and the result matched the APK being offered.

This is called a **reproducible build**. It is useful because it reduces the chance that the APK contains hidden changes that are not present in the public source code.

### Sources covered

| Source | What ObtainX checks |
|---|---|
| **F-Droid official** | The exact package and version-code report from F-Droid's Verification Server. |
| **IzzyOnDroid** | Izzy reproducible build test data when available. |
| **F-Droid third-party repo** | Reproducible metadata included in the repo index, when available. |

### The toggle

For F-Droid, Izzy, and F-Droid third-party repo apps, the app's additional options show:

**Enforce build verification**

> Block updates when F-Droid flags the release for not matching the binary built from source.

When this is **off**, ObtainX still shows a green **Verified Build** badge if the source confirms a reproducible build — but a non-verified build shows **no badge at all**, and nothing is blocked.

When this is **on**, the warning badges below appear, and ObtainX blocks installation unless the build is verified.

### Possible results

| Result (badge) | What happened | Shown when |
|---|---|---|
| **Verified Build** | The APK has reproducible build proof. | Always (toggle on or off). |
| **Mismatched Build** | The source has verification data, and it says this build does not match. | Only when **Enforce** is on. |
| **No Verification Data** | The source does not publish reproducible build data for this app or build. | Only when **Enforce** is on. |
| **Can't Check** | ObtainX could not complete the check (network failure, server error, metadata fetch failed, or parse problem). | Only when **Enforce** is on. |

### What enforcement blocks

When **Enforce build verification** is on and the build is not verified, ObtainX stops the install and explains why, for example:

- *Reproducible build enforcement failed: build is not reproducible* (Mismatched Build)
- *Reproducible build enforcement failed: no verification data is available* (No Verification Data)
- *Reproducible build enforcement failed: could not check build status* (Can't Check)

### Important limitation

If an app is built by F-Droid itself, it may not always have separate reproducible build data in the place ObtainX checks. That should be shown as **No Verification Data**, not as **Mismatched Build**.

**Mismatched Build** should only mean the source provided verification data and the build failed that verification.

---

## Feature 2: GitHub build verification

### What it means

When a developer builds an app on GitHub, GitHub can attach **attestations** to the release files — signed records that vouch for how a specific file was built.

In plain language:

> GitHub kept a signed record of building this exact file, and ObtainX found a record that matches your download.

To match them up, ObtainX takes a unique fingerprint of the file you downloaded and asks GitHub whether it holds a matching record.

### The setting

For GitHub apps, additional options show **GitHub Build Verification**, with three modes:

| Mode | What it does | Badges shown? |
|---|---|---|
| **Off** | Do nothing. Saves GitHub API calls. | No. |
| **Audit Only** | Check the build and show the result badge, but do not block installation. | Yes. |
| **Enforce** | Check the build, show the result badge, and block installation unless the build is verified. | Yes. |

GitHub build verification requires a **validated GitHub personal access token** in **Settings → Source-specific**. This avoids immediately running into GitHub's low unauthenticated API limits. Until a token is validated, the mode cannot be turned on.

### Possible results

| Result (badge) | What happened |
|---|---|
| **Verified Build** | GitHub had a matching signed record for the exact file you downloaded. |
| **Unverified Build** | GitHub had no matching record for that exact file. This does not prove tampering — it means the expected GitHub proof was not found. |
| **Can't Check** | ObtainX could not complete the GitHub check (rate limit, token problem, network failure, API error, or a missing file fingerprint). |

### Why GitHub has no "Mismatched Build" result

For GitHub, ObtainX only checks whether a matching signed record exists for your exact file. It does not go a step further and inspect a record that exists but turns out to be invalid or contradictory. So there is no GitHub "mismatch" result — only proof found or proof not found.

Because of that, GitHub only shows:

- **Verified Build** when exact proof exists.
- **Unverified Build** when exact proof is missing.
- **Can't Check** when the check could not run.

---

## When ObtainX re-checks a build

These verification lookups talk to the internet (and, for GitHub, count against your API limits), so ObtainX avoids repeating them on every single update check when the answer can't have changed. The rule of thumb:

> ObtainX always re-checks when a **new version** appears. Between versions, it reuses the last result — *unless* that result is one that could still improve on its own, in which case it keeps checking.

The two checks behave differently here, because the two systems publish their proof at different times:

| Source | Once the result is **Verified Build** | Other "no proof" results | If the result is **Can't Check** |
|---|---|---|---|
| **F-Droid / Izzy** | Kept for the current version — not re-checked until a new version arrives. | **No Verification Data** / **Mismatched Build**: **keeps re-checking on every update check.** | Keeps re-checking. |
| **GitHub** | Kept for the current version. | **Unverified Build**: kept for the current version — not re-checked until a new version arrives. | Keeps re-checking until it gets a real answer. |

Why the difference for an unverified result:

- **F-Droid / Izzy:** a freshly released build can start out as **No Verification Data** and then turn into **Verified Build** a few hours later. This is normal: the reproducible-build check is finished *after* the app is published, so the proof shows up later for the same version. ObtainX keeps re-checking these until they become verified, so you don't get stuck looking at an outdated "no data" result.
- **GitHub:** the proof is published *together with* the release and is tied to that exact file — it is not added afterward. So an **Unverified Build** result won't change for the same version, and re-asking would only waste API calls. ObtainX keeps that answer until a new version appears.

In both cases, a **Can't Check** result is always retried later, because that just means the check itself couldn't run that time (network, rate limit, etc.) — not that there's a real answer to keep.

---

## What these checks do not prove

Build verification is not the same as app safety.

These checks do **not** prove that:

- the app has no malware,
- the app has no trackers,
- the developer is trustworthy,
- the source code itself is safe,
- the release is the version you personally want,
- Android permissions are harmless.

They only help answer whether the APK has the expected build proof from that source.

---

## Practical advice

- Prefer **Verified Build** when available.
- Treat **Mismatched Build** as a serious warning.
- Treat **Unverified Build** as "no GitHub proof found", not automatic proof of tampering.
- Treat **No Verification Data** as normal for apps or sources that do not publish this metadata.
- Treat **Can't Check** as temporary or configuration-related until proven otherwise.
- For GitHub, use **Audit Only** first to see how many of your apps publish attestations before you start blocking installs.
- Use **Enforce** (either check) only when you are comfortable skipping updates that lack proof.
- Keep in mind the two checks behave differently: for F-Droid/Izzy, warning badges show up **only** once you turn on enforcement; for GitHub, they also show up in Audit Only.
