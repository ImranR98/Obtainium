FROM ubuntu:22.04

ENV DEBIAN_FRONTEND noninteractive
ENV ANDROID_SDK_ROOT /opt/android-sdk-linux
ENV PATH "${PATH}:/opt/flutter/bin:/root/.pub-cache/bin:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:/opt/android-sdk-linux/platform-tools"

ENV HOME=/root

# Prereqs
RUN \
    apt-get update &&\
    apt-get install -y --no-install-recommends \
        bash \
        curl \
        file \
        git 2.x \
        unzip \
        xz-utils \
        zip \
        libglu1-mesa \
        libxi-dev \
        libxmu-dev \
        libglu1-mesa-dev \
        git-lfs \
        openssl \
        wget

# Build prereqs
RUN \
    apt-get install -y \
        cmake curl git wget unzip libgconf-2-4 gdb libstdc++6 libglu1-mesa fonts-droid-fallback lib32stdc++6 python3 sed \
        cmake ninja-build build-essential libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev clang pkg-config libgtk-3-dev \
        liblzma-dev libmount-dev libblkid-dev libgcrypt20-dev libgpg-error-dev libssl-dev libpng-dev libjpeg-dev \
        libtiff-dev libgif-dev libgtk-3-dev

# Android SDK prequisites
# https://developer.android.com/studio#command-tools
RUN \
    apt-get install -y --no-install-recommends \
        git \
        git-lfs \
        openssl \
        wget \
        unzip

# Android SDK
RUN \
    wget --quiet  https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip -O /tmp/tools.zip && \
    mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools && \
    unzip -q /tmp/tools.zip -d ${ANDROID_SDK_ROOT}/cmdline-tools && \
    mv ${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest && \
    rm -v /tmp/tools.zip && \
    mkdir -p /root/.android/ && touch /root/.android/repositories.cfg &&\
    apt-get install -y --no-install-recommends openjdk-17-jdk openjdk-17-jre &&\
    yes | sdkmanager --licenses &&\
    sdkmanager --update

    # Platform tools
# Get latest with sdkmanager --list
RUN sdkmanager --install "build-tools;33.0.1"
RUN sdkmanager --install "ndk;26.3.11579264"
RUN sdkmanager --install "cmake;4.0.2"
RUN sdkmanager --install platform-tools
RUN sdkmanager --install emulator
RUN sdkmanager --install tools
RUN sdkmanager --install "platforms;android-28"
RUN sdkmanager --install "platforms;android-31"
RUN sdkmanager --install "platforms;android-32"
RUN sdkmanager --install "platforms;android-33"
RUN sdkmanager --install "platforms;android-34"
RUN sdkmanager --install "platforms;android-35"

# Flutter
ARG DEV_UID=0
RUN \
    wget --quiet https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.29.3-stable.tar.xz -O /tmp/flutter.tar.xz &&\
    mkdir -p /opt &&\
    cd /opt &&\
    tar xf /tmp/flutter.tar.xz &&\
    rm /tmp/flutter.tar.xz &&\
    git config --global --add safe.directory /opt/flutter &&\
    dart pub global activate cider &&\
    chown -R ${DEV_UID} /opt/flutter
RUN flutter --disable-analytics
RUN flutter upgrade
RUN chmod a+w /opt/flutter/packages -R
