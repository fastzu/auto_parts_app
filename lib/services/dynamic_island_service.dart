import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';

class DynamicIslandService {
  DynamicIslandService._();
  static final DynamicIslandService instance = DynamicIslandService._();

  static const String appGroupId = 'group.com.autoparts.app';
  final LiveActivities _plugin = LiveActivities();
  final Map<String, String> _activeIds = {};
  bool _initialized = false;

  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _ensureInit() async {
    if (!_isIos || _initialized) {
      return;
    }
    try {
      await _plugin.init(appGroupId: appGroupId, urlScheme: 'autoparts');
      _initialized = true;
    } catch (_) {}
  }

  Future<void> syncProgress({
    required String keyId,
    required String title,
    required String statusText,
    required double progress, // 0.0 -> 1.0
    String etaOrDistance = '',
  }) async {
    if (!_isIos) {
      return;
    }
    await _ensureInit();
    try {
      final supported = await _plugin.areActivitiesSupported();
      if (!supported) {
        return;
      }

      final payload = <String, dynamic>{
        'title': title,
        'statusText': statusText,
        'progress': progress.clamp(0.0, 1.0),
        'etaOrDistance': etaOrDistance,
      };

      final existingActivityId = _activeIds[keyId];
      if (existingActivityId != null) {
        await _plugin.updateActivity(existingActivityId, payload);
      } else {
        final createdId = await _plugin.createActivity(keyId, payload);
        if (createdId != null) {
          _activeIds[keyId] = createdId;
        }
      }
    } catch (_) {}
  }

  Future<void> endProgress(String keyId) async {
    if (!_isIos) {
      return;
    }
    final existingActivityId = _activeIds.remove(keyId);
    if (existingActivityId == null) {
      return;
    }
    try {
      await _plugin.endActivity(existingActivityId);
    } catch (_) {}
  }
}