import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

class AppsFilter {
  late String nameFilter;
  late String authorFilter;
  late String idFilter;
  late bool includeUptodate;
  late bool includeNonInstalled;
  late Set<String> categoryFilter;
  late String sourceFilter;

  AppsFilter({
    this.nameFilter = '',
    this.authorFilter = '',
    this.idFilter = '',
    this.includeUptodate = true,
    this.includeNonInstalled = true,
    this.categoryFilter = const {},
    this.sourceFilter = '',
  });

  Map<String, dynamic> toFormValuesMap() {
    return {
      'appName': nameFilter,
      'author': authorFilter,
      'appId': idFilter,
      'upToDateApps': includeUptodate,
      'nonInstalledApps': includeNonInstalled,
      'sourceFilter': sourceFilter,
    };
  }

  void setFormValuesFromMap(Map<String, dynamic> values) {
    nameFilter = values['appName']!;
    authorFilter = values['author']!;
    idFilter = values['appId']!;
    includeUptodate = values['upToDateApps'];
    includeNonInstalled = values['nonInstalledApps'];
    sourceFilter = values['sourceFilter'];
  }

  bool isIdenticalTo(AppsFilter other, SettingsProvider settingsProvider) =>
      authorFilter.trim() == other.authorFilter.trim() &&
      nameFilter.trim() == other.nameFilter.trim() &&
      idFilter.trim() == other.idFilter.trim() &&
      includeUptodate == other.includeUptodate &&
      includeNonInstalled == other.includeNonInstalled &&
      settingsProvider.setEqual(categoryFilter, other.categoryFilter) &&
      sourceFilter.trim() == other.sourceFilter.trim();
}

class AppListBuilder {
  static List<AppInMemory> filter(
    List<AppInMemory> apps,
    AppsFilter filter,
    SourceProvider sourceProvider,
  ) {
    final nameTokens = filter.nameFilter.isNotEmpty
        ? filter.nameFilter
            .split(' ')
            .where((element) => element.trim().isNotEmpty)
            .toList()
        : const <String>[];
    final authorTokens = filter.authorFilter.isNotEmpty
        ? filter.authorFilter
            .split(' ')
            .where((element) => element.trim().isNotEmpty)
            .toList()
        : const <String>[];

    return apps.where((app) {
      if (app.app.installedVersion == app.app.latestVersion &&
          !(filter.includeUptodate)) {
        return false;
      }
      if (app.app.installedVersion == null && !(filter.includeNonInstalled)) {
        return false;
      }
      for (var t in nameTokens) {
        if (!app.name.toLowerCase().contains(t.toLowerCase())) {
          return false;
        }
      }
      for (var t in authorTokens) {
        if (!app.author.toLowerCase().contains(t.toLowerCase())) {
          return false;
        }
      }
      if (filter.idFilter.isNotEmpty) {
        if (!app.app.id.contains(filter.idFilter)) {
          return false;
        }
      }
      if (filter.categoryFilter.isNotEmpty &&
          filter.categoryFilter
              .intersection(app.app.categories.toSet())
              .isEmpty) {
        return false;
      }
      if (filter.sourceFilter.isNotEmpty &&
          sourceProvider
                  .getSource(
                    app.app.url,
                    overrideSource: app.app.overrideSource,
                  )
                  .runtimeType
                  .toString() !=
              filter.sourceFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  static List<AppInMemory> sort(
    List<AppInMemory> apps,
    SortColumnSettings sortColumn,
    SortOrderSettings sortOrder,
  ) {
    if (sortColumn == SortColumnSettings.added) return apps;

    final isDesc = sortOrder == SortOrderSettings.descending;
    if (sortColumn == SortColumnSettings.releaseDate) {
      var entries = apps
          .map((a) => MapEntry(a.app.releaseDate, a))
          .toList()
        ..sort((a, b) {
          final aDate = a.key;
          final bDate = b.key;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return isDesc
              ? bDate.compareTo(aDate)
              : aDate.compareTo(bDate);
        });
      apps = entries.map((e) => e.value).toList();
    } else {
      String keyFn(AppInMemory a) => switch (sortColumn) {
        SortColumnSettings.authorName =>
          (a.author + a.name).toLowerCase(),
        SortColumnSettings.nameAuthor =>
          (a.name + a.author).toLowerCase(),
        _ => '',
      };
      var entries = apps
          .map((a) => MapEntry(keyFn(a), a))
          .toList()
        ..sort((a, b) => (a.key as String).compareTo(b.key as String));
      apps = entries.map((e) => e.value).toList();
      if (isDesc) {
        apps = apps.reversed.toList();
      }
    }
    return apps;
  }

  static List<AppInMemory> reorder(
    List<AppInMemory> apps,
    bool pinUpdates,
    bool buryNonInstalled,
    Set<String> existingUpdates,
  ) {
    if (pinUpdates) {
      var temp = <AppInMemory>[];
      apps = apps.where((sa) {
        if (existingUpdates.contains(sa.app.id)) {
          temp.add(sa);
          return false;
        }
        return true;
      }).toList();
      apps = [...temp, ...apps];
    }

    if (buryNonInstalled) {
      var temp = <AppInMemory>[];
      apps = apps.where((sa) {
        if (sa.app.installedVersion == null) {
          temp.add(sa);
          return false;
        }
        return true;
      }).toList();
      apps = [...apps, ...temp];
    }

    var tempRenamed = <AppInMemory>[];
    var tempPinned = <AppInMemory>[];
    var tempNotPinned = <AppInMemory>[];
    for (var a in apps) {
      if (a.app.hasPendingRepoRename) {
        tempRenamed.add(a);
      } else if (a.app.pinned) {
        tempPinned.add(a);
      } else {
        tempNotPinned.add(a);
      }
    }
    apps = [...tempRenamed, ...tempPinned, ...tempNotPinned];

    return apps;
  }
}
