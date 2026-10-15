import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../models/episode.dart';
import '../models/placement_test.dart';

/// Reads the bundled content (40 episodes + placement test) from the assets.
/// Everything is cached after the first read.
class ContentRepository {
  ContentRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final Map<int, Episode> _episodes = {};
  PlacementTest? _placementTest;

  static const placementTestPath = 'assets/data/placement_test_logic.json';

  static String episodePath(int id) =>
      'assets/data/episodes/episode_${id.toString().padLeft(2, '0')}.json';

  Future<Episode> loadEpisode(int id) async {
    RangeError.checkValueInInterval(id, 1, AppRules.totalEpisodes, 'id');
    final cached = _episodes[id];
    if (cached != null) return cached;

    final json = await _loadJsonObject(episodePath(id));
    final episode = Episode.fromJson(json);
    if (episode.id != id) {
      throw FormatException(
          '${episodePath(id)} contains episode ${episode.id}, expected $id');
    }
    return _episodes[id] = episode;
  }

  /// All 40 episodes, in order.
  Future<List<Episode>> loadAllEpisodes() => Future.wait([
        for (var id = 1; id <= AppRules.totalEpisodes; id++) loadEpisode(id),
      ]);

  Future<PlacementTest> loadPlacementTest() async {
    final cached = _placementTest;
    if (cached != null) return cached;
    final json = await _loadJsonObject(placementTestPath);
    return _placementTest = PlacementTest.fromJson(json);
  }

  Future<Map<String, dynamic>> _loadJsonObject(String path) async {
    final raw = await _bundle.loadString(path);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('$path is not a JSON object');
    }
    return decoded;
  }
}
