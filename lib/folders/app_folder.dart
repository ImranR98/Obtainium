import 'dart:math';

import 'package:obtainium/providers/source_provider.dart';

enum FolderRuleField { name, author, category, source }

enum FolderRuleMatchType { contains, equals, startsWith }

enum FolderConditionIntent { neutral, include, exclude }

enum FolderCategoryMatchMode { any, all }

enum FolderMembershipOverride { automatic, include, exclude }

const int folderCriteriaMigrationVersion = 1;

class FolderTextCriterion {
  final String query;
  final FolderRuleMatchType matchType;
  final bool tokenizeContains;
  final bool caseSensitive;

  const FolderTextCriterion({
    required this.query,
    this.matchType = FolderRuleMatchType.contains,
    this.tokenizeContains = false,
    this.caseSensitive = false,
  });

  bool get isEmpty => query.trim().isEmpty;

  bool matches(String target) {
    if (isEmpty) return true;
    final normalizedTarget = caseSensitive ? target : target.toLowerCase();
    final normalizedQuery = caseSensitive
        ? query.trim()
        : query.trim().toLowerCase();
    final values = tokenizeContains && matchType == FolderRuleMatchType.contains
        ? normalizedQuery
              .split(RegExp(r'\s+'))
              .where((value) => value.isNotEmpty)
        : <String>[normalizedQuery];

    return values.every((value) {
      return switch (matchType) {
        FolderRuleMatchType.contains => normalizedTarget.contains(value),
        FolderRuleMatchType.equals => normalizedTarget == value,
        FolderRuleMatchType.startsWith => normalizedTarget.startsWith(value),
      };
    });
  }

  Map<String, dynamic> toJson() => {
    'query': query,
    'matchType': matchType.name,
    if (tokenizeContains) 'tokenizeContains': true,
    if (caseSensitive) 'caseSensitive': true,
  };

  factory FolderTextCriterion.fromJson(Map<String, dynamic> json) {
    return FolderTextCriterion(
      query: json['query'] as String? ?? '',
      matchType: FolderRuleMatchType.values.firstWhere(
        (value) => value.name == json['matchType'],
        orElse: () => FolderRuleMatchType.contains,
      ),
      tokenizeContains: json['tokenizeContains'] == true,
      caseSensitive: json['caseSensitive'] == true,
    );
  }
}

class FolderCriteria {
  final FolderTextCriterion? name;
  final FolderTextCriterion? author;
  final Set<String> includedCategories;
  final Set<String> excludedCategories;
  final FolderCategoryMatchMode categoryMatchMode;
  final FolderRuleMatchType categoryMatchType;
  final bool categoryCaseSensitive;
  final FolderTextCriterion? source;
  final FolderConditionIntent installedIntent;
  final FolderConditionIntent upToDateIntent;
  final FolderConditionIntent trackOnlyIntent;

  FolderCriteria({
    this.name,
    this.author,
    Set<String> includedCategories = const {},
    Set<String> excludedCategories = const {},
    this.categoryMatchMode = FolderCategoryMatchMode.any,
    this.categoryMatchType = FolderRuleMatchType.equals,
    this.categoryCaseSensitive = true,
    this.source,
    this.installedIntent = FolderConditionIntent.neutral,
    this.upToDateIntent = FolderConditionIntent.neutral,
    this.trackOnlyIntent = FolderConditionIntent.neutral,
  }) : includedCategories = Set<String>.from(includedCategories),
       excludedCategories = Set<String>.from(excludedCategories);

  bool get isEmpty =>
      (name == null || name!.isEmpty) &&
      (author == null || author!.isEmpty) &&
      includedCategories.isEmpty &&
      excludedCategories.isEmpty &&
      (source == null || source!.isEmpty) &&
      installedIntent == FolderConditionIntent.neutral &&
      upToDateIntent == FolderConditionIntent.neutral &&
      trackOnlyIntent == FolderConditionIntent.neutral;

  int get activeConditionCount {
    var count = 0;
    if (name != null && !name!.isEmpty) count++;
    if (author != null && !author!.isEmpty) count++;
    if (includedCategories.isNotEmpty || excludedCategories.isNotEmpty) count++;
    if (source != null && !source!.isEmpty) count++;
    if (installedIntent != FolderConditionIntent.neutral) count++;
    if (upToDateIntent != FolderConditionIntent.neutral) count++;
    if (trackOnlyIntent != FolderConditionIntent.neutral) count++;
    return count;
  }

  bool matches(
    App app, {
    required String sourceIdentifier,
    required bool isUpToDate,
  }) {
    if (isEmpty) return false;
    if (name != null && !name!.matches(app.finalName)) return false;
    if (author != null && !author!.matches(app.finalAuthor)) return false;
    if (source != null && !source!.matches(sourceIdentifier)) return false;
    if (!_categoriesMatch(app.categories)) return false;
    if (!_intentMatches(app.installedVersion != null, installedIntent)) {
      return false;
    }
    if (!_intentMatches(isUpToDate, upToDateIntent)) return false;
    if (!_intentMatches(
      app.additionalSettings['trackOnly'] == true,
      trackOnlyIntent,
    )) {
      return false;
    }
    return true;
  }

  bool _categoriesMatch(Iterable<String> appCategories) {
    bool categoryMatches(String category, String query) {
      final target = categoryCaseSensitive ? category : category.toLowerCase();
      final value = categoryCaseSensitive ? query : query.toLowerCase();
      return switch (categoryMatchType) {
        FolderRuleMatchType.contains => target.contains(value),
        FolderRuleMatchType.equals => target == value,
        FolderRuleMatchType.startsWith => target.startsWith(value),
      };
    }

    final categories = appCategories.toList(growable: false);
    final hasExcludedMatch = excludedCategories.any(
      (query) => categories.any((category) => categoryMatches(category, query)),
    );
    if (hasExcludedMatch) return false;
    if (includedCategories.isEmpty) return true;

    return switch (categoryMatchMode) {
      FolderCategoryMatchMode.any => includedCategories.any(
        (query) =>
            categories.any((category) => categoryMatches(category, query)),
      ),
      FolderCategoryMatchMode.all => includedCategories.every(
        (query) =>
            categories.any((category) => categoryMatches(category, query)),
      ),
    };
  }

  bool _intentMatches(bool value, FolderConditionIntent intent) {
    return switch (intent) {
      FolderConditionIntent.neutral => true,
      FolderConditionIntent.include => value,
      FolderConditionIntent.exclude => !value,
    };
  }

  Map<String, dynamic> toJson() => {
    if (name != null && !name!.isEmpty) 'name': name!.toJson(),
    if (author != null && !author!.isEmpty) 'author': author!.toJson(),
    if (includedCategories.isNotEmpty)
      'includedCategories': includedCategories.toList(),
    if (excludedCategories.isNotEmpty)
      'excludedCategories': excludedCategories.toList(),
    if (includedCategories.isNotEmpty || excludedCategories.isNotEmpty) ...{
      'categoryMatchMode': categoryMatchMode.name,
      'categoryMatchType': categoryMatchType.name,
      'categoryCaseSensitive': categoryCaseSensitive,
    },
    if (source != null && !source!.isEmpty) 'source': source!.toJson(),
    if (installedIntent != FolderConditionIntent.neutral)
      'installedIntent': installedIntent.name,
    if (upToDateIntent != FolderConditionIntent.neutral)
      'upToDateIntent': upToDateIntent.name,
    if (trackOnlyIntent != FolderConditionIntent.neutral)
      'trackOnlyIntent': trackOnlyIntent.name,
  };

  factory FolderCriteria.fromJson(Map<String, dynamic> json) {
    FolderTextCriterion? textCriterion(String key) {
      final value = json[key];
      return value is Map<String, dynamic>
          ? FolderTextCriterion.fromJson(value)
          : value is Map
          ? FolderTextCriterion.fromJson(Map<String, dynamic>.from(value))
          : null;
    }

    FolderConditionIntent intent(String key) {
      return FolderConditionIntent.values.firstWhere(
        (value) => value.name == json[key],
        orElse: () => FolderConditionIntent.neutral,
      );
    }

    return FolderCriteria(
      name: textCriterion('name'),
      author: textCriterion('author'),
      includedCategories: Set<String>.from(
        json['includedCategories'] as List? ?? const [],
      ),
      excludedCategories: Set<String>.from(
        json['excludedCategories'] as List? ?? const [],
      ),
      categoryMatchMode: FolderCategoryMatchMode.values.firstWhere(
        (value) => value.name == json['categoryMatchMode'],
        orElse: () => FolderCategoryMatchMode.any,
      ),
      categoryMatchType: FolderRuleMatchType.values.firstWhere(
        (value) => value.name == json['categoryMatchType'],
        orElse: () => FolderRuleMatchType.equals,
      ),
      categoryCaseSensitive: json['categoryCaseSensitive'] != false,
      source: textCriterion('source'),
      installedIntent: intent('installedIntent'),
      upToDateIntent: intent('upToDateIntent'),
      trackOnlyIntent: intent('trackOnlyIntent'),
    );
  }

  factory FolderCriteria.fromLegacyRule(FolderRule rule) {
    final textCriterion = FolderTextCriterion(
      query: rule.value,
      matchType: rule.matchType,
    );
    return switch (rule.field) {
      FolderRuleField.name => FolderCriteria(name: textCriterion),
      FolderRuleField.author => FolderCriteria(author: textCriterion),
      FolderRuleField.category => FolderCriteria(
        includedCategories: {rule.value},
        categoryMatchType: rule.matchType,
        categoryCaseSensitive: false,
      ),
      FolderRuleField.source => FolderCriteria(source: textCriterion),
    };
  }
}

class FolderRule {
  final FolderRuleField field;
  final FolderRuleMatchType matchType;
  final String value;

  const FolderRule({
    required this.field,
    required this.matchType,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
    'field': field.name,
    'matchType': matchType.name,
    'value': value,
  };

  factory FolderRule.fromJson(Map<String, dynamic> json) => FolderRule(
    field: FolderRuleField.values.firstWhere(
      (value) => value.name == json['field'],
      orElse: () => FolderRuleField.name,
    ),
    matchType: FolderRuleMatchType.values.firstWhere(
      (value) => value.name == json['matchType'],
      orElse: () => FolderRuleMatchType.contains,
    ),
    value: json['value'] as String? ?? '',
  );
}

class AppFolder {
  final String id;
  final String name;
  final FolderCriteria? criteria;
  final bool loadedFromLegacyRule;

  const AppFolder({
    required this.id,
    required this.name,
    this.criteria,
    this.loadedFromLegacyRule = false,
  });

  bool get isSmart => criteria != null && !criteria!.isEmpty;

  AppFolder copyWith({
    String? name,
    FolderCriteria? criteria,
    bool clearCriteria = false,
  }) => AppFolder(
    id: id,
    name: name ?? this.name,
    criteria: clearCriteria ? null : (criteria ?? this.criteria),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (isSmart) 'criteria': criteria!.toJson(),
  };

  factory AppFolder.fromJson(Map<String, dynamic> json) {
    final criteriaJson = json['criteria'];
    if (criteriaJson is Map) {
      return AppFolder(
        id: json['id'] as String,
        name: json['name'] as String,
        criteria: FolderCriteria.fromJson(
          Map<String, dynamic>.from(criteriaJson),
        ),
      );
    }

    final legacyRuleJson = json['rule'];
    final legacyRule = legacyRuleJson is Map
        ? FolderRule.fromJson(Map<String, dynamic>.from(legacyRuleJson))
        : null;
    return AppFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      criteria: legacyRule == null
          ? null
          : FolderCriteria.fromLegacyRule(legacyRule),
      loadedFromLegacyRule: legacyRule != null,
    );
  }

  static String generateId() {
    final rand = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final randomSuffix = List.generate(
      6,
      (_) => rand.nextInt(36).toRadixString(36),
    ).join();
    return '$timestamp$randomSuffix';
  }
}

bool reconcileAppFolderMemberships(
  App app,
  Iterable<AppFolder> folders, {
  required String sourceIdentifier,
  required bool isUpToDate,
  bool migrateLegacyRules = false,
}) {
  final beforeIds = folderIdsForApp(app).toSet();
  final beforeOverrides = folderOverridesForApp(app);
  final beforeNames = Map<String, dynamic>.from(
    app.additionalSettings['folderNames'] as Map? ?? {},
  );
  final beforeLegacyExcluded = Set<String>.from(
    app.additionalSettings['excludedFolderIds'] as List? ?? const [],
  );
  final isOnDemandOnly = app.additionalSettings['onDemandOnly'] == true;

  for (final folder in folders) {
    if (!folder.isSmart) continue;
    final criteriaMatches =
        !isOnDemandOnly &&
        folder.criteria!.matches(
          app,
          sourceIdentifier: sourceIdentifier,
          isUpToDate: isUpToDate,
        );

    if (migrateLegacyRules) {
      if (beforeLegacyExcluded.contains(folder.id)) {
        setFolderMembershipOverride(
          app,
          folder.id,
          FolderMembershipOverride.exclude,
          folder.name,
        );
      } else if (folder.loadedFromLegacyRule &&
          beforeIds.contains(folder.id) &&
          !criteriaMatches) {
        setFolderMembershipOverride(
          app,
          folder.id,
          FolderMembershipOverride.include,
          folder.name,
        );
      }
    }

    final override = folderOverrideForApp(app, folder.id);
    final shouldBelong = switch (override) {
      FolderMembershipOverride.automatic => criteriaMatches,
      FolderMembershipOverride.include => true,
      FolderMembershipOverride.exclude => false,
    };
    setAppFolderMembership(app, folder.id, folder.name, belongs: shouldBelong);
  }

  if (migrateLegacyRules) {
    app.additionalSettings.remove('excludedFolderIds');
  }

  final afterIds = folderIdsForApp(app).toSet();
  final afterOverrides = folderOverridesForApp(app);
  final afterNames = Map<String, dynamic>.from(
    app.additionalSettings['folderNames'] as Map? ?? {},
  );
  final afterLegacyExcluded = Set<String>.from(
    app.additionalSettings['excludedFolderIds'] as List? ?? const [],
  );
  return !_setsEqual(beforeIds, afterIds) ||
      !_mapsEqual(beforeOverrides, afterOverrides) ||
      !_mapsEqual(beforeNames, afterNames) ||
      !_setsEqual(beforeLegacyExcluded, afterLegacyExcluded);
}

bool _setsEqual<T>(Set<T> first, Set<T> second) {
  return first.length == second.length && first.containsAll(second);
}

bool _mapsEqual<K, V>(Map<K, V> first, Map<K, V> second) {
  if (first.length != second.length) return false;
  for (final entry in first.entries) {
    if (!second.containsKey(entry.key) || second[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

List<String> folderIdsForApp(App app) {
  final raw = app.additionalSettings['folderIds'];
  if (raw == null) return [];
  return List<String>.from(raw as List);
}

Map<String, String> folderOverridesForApp(App app) {
  final raw = app.additionalSettings['folderOverrides'];
  if (raw is! Map) return {};
  return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
}

FolderMembershipOverride folderOverrideForApp(App app, String folderId) {
  final stored = folderOverridesForApp(app)[folderId];
  if (stored != null) {
    return FolderMembershipOverride.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => FolderMembershipOverride.automatic,
    );
  }
  if (excludedFolderIdsForApp(app).contains(folderId)) {
    return FolderMembershipOverride.exclude;
  }
  return FolderMembershipOverride.automatic;
}

List<String> excludedFolderIdsForApp(App app) {
  final overrideIds = folderOverridesForApp(app).entries
      .where((entry) => entry.value == FolderMembershipOverride.exclude.name)
      .map((entry) => entry.key);
  final raw = app.additionalSettings['excludedFolderIds'];
  final legacyIds = raw == null
      ? const <String>[]
      : List<String>.from(raw as List);
  return {...overrideIds, ...legacyIds}.toList();
}

void setFolderMembershipOverride(
  App app,
  String folderId,
  FolderMembershipOverride override,
  String folderName,
) {
  final overrides = folderOverridesForApp(app);
  if (override == FolderMembershipOverride.automatic) {
    overrides.remove(folderId);
  } else {
    overrides[folderId] = override.name;
  }
  app.additionalSettings['folderOverrides'] = overrides;

  // Only drop this folder's stale entry from the pre-criteria legacy list;
  // never fold override-derived excludes back into it. Exclusions now live
  // solely in [folderOverrides]; merging them here would pollute the legacy
  // list and could resurrect an exclusion after its override is cleared.
  final rawLegacy = app.additionalSettings['excludedFolderIds'];
  if (rawLegacy is List) {
    final legacyExcluded = List<String>.from(rawLegacy)..remove(folderId);
    if (legacyExcluded.isEmpty) {
      app.additionalSettings.remove('excludedFolderIds');
    } else {
      app.additionalSettings['excludedFolderIds'] = legacyExcluded;
    }
  }

  if (override == FolderMembershipOverride.include) {
    setAppFolderMembership(app, folderId, folderName, belongs: true);
  } else if (override == FolderMembershipOverride.exclude) {
    setAppFolderMembership(app, folderId, folderName, belongs: false);
  }
}

void setAppFolderMembership(
  App app,
  String folderId,
  String folderName, {
  required bool belongs,
}) {
  final ids = folderIdsForApp(app).toSet();
  final Map<String, dynamic> folderNames = Map<String, dynamic>.from(
    app.additionalSettings['folderNames'] as Map? ?? {},
  );
  if (belongs) {
    ids.add(folderId);
    folderNames[folderId] = folderName;
  } else {
    ids.remove(folderId);
    folderNames.remove(folderId);
  }
  app.additionalSettings['folderIds'] = ids.toList();
  app.additionalSettings['folderNames'] = folderNames;
}

void addAppToFolder(App app, String folderId, String folderName) {
  setAppFolderMembership(app, folderId, folderName, belongs: true);
  final excluded = excludedFolderIdsForApp(app).toSet()..remove(folderId);
  app.additionalSettings['excludedFolderIds'] = excluded.toList();
}

void removeAppFromFolder(App app, String folderId) {
  setAppFolderMembership(app, folderId, '', belongs: false);
  final excluded = excludedFolderIdsForApp(app).toSet()..add(folderId);
  app.additionalSettings['excludedFolderIds'] = excluded.toList();
}

void clearFolderFromApp(App app, String folderId) {
  setAppFolderMembership(app, folderId, '', belongs: false);
  final excluded = excludedFolderIdsForApp(app).toSet()..remove(folderId);
  app.additionalSettings['excludedFolderIds'] = excluded.toList();
  final overrides = folderOverridesForApp(app)..remove(folderId);
  app.additionalSettings['folderOverrides'] = overrides;
}

/// Removes every folder association from [app] — memberships, names, overrides,
/// and the legacy excluded list.
///
/// Enforces the invariant that an On-Demand Only app belongs to no folder:
/// on-demand and folders are mutually exclusive everywhere in the UI (folder
/// views/counts skip on-demand apps, and smart-folder reconciliation forces
/// them out), so an on-demand app must never carry stale, hidden memberships.
/// Call this whenever an app is marked on-demand. Clearing overrides too gives
/// a clean slate: if the app later leaves on-demand, smart folders re-evaluate
/// from scratch rather than resurrecting a pre-on-demand membership.
void clearAllFoldersFromApp(App app) {
  app.additionalSettings.remove('folderIds');
  app.additionalSettings.remove('folderNames');
  app.additionalSettings.remove('folderOverrides');
  app.additionalSettings.remove('excludedFolderIds');
}
