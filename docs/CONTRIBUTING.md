# Contributing to Obtanium!

Policies and procedures on contributing to Obtanium.

## Bug Reports / Testing

Welcomed!

If you want to be excellent, please consider implementing this guide, [The Art Of The Bug Report](https://www.ministryoftesting.com/insights/11b82aee), when writing bug reports.

And for any testers out there [How to think like a Tester](https://medium.com/@blakenorrish/how-to-think-like-a-tester-7a174ff6aeaf) is a good introduction.

## Development

Please see the [developer guide](docs/DEVELOPER_GUIDE.md) for in-depth details about Obtanium's architecture.

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
