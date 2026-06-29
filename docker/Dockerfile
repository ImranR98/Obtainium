# Toolchain image: matches the build environment in
# .github/workflows/release.yml — ubuntu-latest -> ubuntu:24.04,
# actions/setup-java -> Temurin JDK 21, and AGP-managed Android build-tools/NDK
# (CI pins none) — BUT Flutter is intentionally NOT installed here.
#
# Flutter comes from the repo's pinned .flutter submodule (mounted at runtime by
# docker/builder.sh), so the Flutter version stays reproducible and matches
# build.sh. (This is the one deliberate divergence from release.yml, which uses
# the floating `stable` channel.)
#
# For a fully reproducible image, pin by digest: FROM ubuntu:24.04@sha256:<digest>
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV JAVA_HOME=/opt/java/temurin-21
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH="${PATH}:${JAVA_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools"

# System deps for Flutter Android builds (no Linux desktop / GTK toolchain).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash ca-certificates curl file git git-lfs openssl unzip wget xz-utils zip && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    git config --system --add safe.directory '*'

# Temurin JDK 21 — matches actions/setup-java (distribution: temurin, java-version: 21).
# The Adoptium "latest 21 GA" URL mirrors what setup-java resolves.
RUN mkdir -p /opt/java && \
    wget -q "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse" -O /tmp/jdk.tar.gz && \
    tar -xzf /tmp/jdk.tar.gz -C /opt/java && \
    rm /tmp/jdk.tar.gz && \
    mv /opt/java/jdk-21* "${JAVA_HOME}"

# Android command-line tools + a base SDK. NDK/cmake are deliberately NOT
# pre-installed: AGP auto-downloads them at build time (exactly like CI, which
# pins none; the NDK version still comes from build.gradle.kts). ANDROID_HOME is
# made writable so the non-root runtime user can install them on demand.
ARG CMDLINE_TOOLS_URL=https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && \
    wget -q "${CMDLINE_TOOLS_URL}" -O /tmp/tools.zip && \
    unzip -q /tmp/tools.zip -d ${ANDROID_HOME}/cmdline-tools && \
    mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest && \
    rm /tmp/tools.zip && \
    mkdir -p /root/.android && touch /root/.android/repositories.cfg && \
    yes | sdkmanager --licenses && \
    sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" && \
    chmod -R a+w ${ANDROID_HOME}

# Flutter is provided by the repo's pinned .flutter submodule at runtime
# (see docker/builder.sh), NOT installed in the image.
