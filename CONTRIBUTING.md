# Contributing to Obtanium!

Policies and procedures on contributing to Obtanium.

## Bug Reports

Welcomed!

If you want to be excellent, please consider implementing this guide, [The Art Of The Bug Report](https://www.ministryoftesting.com/insights/11b82aee).

## Development

### Logging

Please use our [AppLogger](lib/core/logging/app_logger.dart) for any internal logging.

There are plenty of examples of it's use in [main.dart](lib/main.dart).

### Style

#### Bracing

Please use the "K&R" bracing style. 

```Kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    intent?.let {
        setIntent(transformShareIntent(it))
    }
    super.onCreate(savedInstanceState)
}
```

#### Indentation

Obtanium is a mixed spacing project; tabs are **not** used. Files will use either four or two spaces as indentation. Please follow the spacing in the current file. New files should use 4 spaces.

## Translations / i18n

User shown text strings are located in `*.json` files in [assets/translations](assets/translations). 
The main template file is [en.json](assets/translations/en.json). At a minimum please add english translations for any new strings to this file.

[standardize.mjs](assets/translations/standardize.mjs) and MTL may be used as a first pass to add translations for other languages, until more apt translations are proposed.

Please also follow the [indentation style](#indentation).
