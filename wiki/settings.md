---
title: Settings
description: Settings explained
---

# Settings

Explainations of the options in Obtainium Settings

## Source Specific

GitHub puts a cap on the number of API requests you can make in a given period of time. Since Obtainium uses the GitHub API to grab release info, you may run into a "rate limit" error if you have more than a few dozen GitHub apps. You can get around this by getting a Personal Access Token.

GitLab releases sometimes contain APKs that are attached in non-standard ways, such that Obtainium cannot get to them easily. The GitLab API provides a far more reliable way to extract APKs but it cannot be used without an API key. While this shouldn't be an issue for most GitLab repos, you can add your own Personal Access Token in Obtainium's settings for more reliable APK extraction in edge cases where it does turn out to be a problem.

### Setting Up Personal Access Tokens

=== ":simple-github: GitHub"
    To avoid API rate limits when tracking GitHub apps:

    1. Login to [GitHub](https://github.com).

    2. Go to the [Fine-grained tokens](https://github.com/settings/tokens?type=beta) section in developer settings.

    3. Select **Generate new token**.

    4. Give your token name and set an expiry date.

    5. Scroll to the bottom and select **Generate token**.

    6. Copy the token and paste it into the Obtainium settings. Make sure to copy your token now as you will not be able to see it again.

=== ":simple-gitlab: GitLab"
    For more reliable APK extraction from GitLab releases:

    1. Login to [GitLab](https://github.com).

    2. Go to the [personal access tokens](https://gitlab.com/-/user_settings/personal_access_tokens) section in settings.

    3. Select **Add new token**.

    4. Give your token name and set an expiration date.

    5. Tick the `read_api` box.

    6. Scroll to the bottom and select **Create personal access token**.

    7. Copy the token and paste it into the Obtainium settings. Make sure to copy your token now as you will not be able to see it again.

    !!! info "When is this needed?"
        See [this explanation](https://github.com/ImranR98/Obtainium/issues/3#issuecomment-1234695412) about non-standard APK attachments in GitLab releases
