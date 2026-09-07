// ============================================================================
// BEAST SMALL ULTIMATE
// ============================================================================
// Single-file on-device recommendation/behavior engine for Flutter.
//
// Included local capabilities:
// - consent + privacy-safe telemetry
// - durable offline event queue + retry/backoff + gzip
// - session/lifecycle/route/network/performance tracking
// - short/medium/long-term behavioral memory
// - interests, dislikes, creator/category/item affinity
// - recency, exposure, repetition and fatigue signals
// - session intent + session momentum
// - Markov-style sequence mining
// - FTRL-style online tag learning
// - Thompson Sampling
// - diagonal LinUCB contextual bandit
// - two-tower-style local vector scoring when embeddings are supplied
// - multi-objective ranking
// - MMR diversity
// - cold-start levels
// - explainable recommendations
// - user controls: hide / less-like / more-like / topic preferences
// - time-aware and social/context signals
// - local segmentation + churn/LTV heuristics
// - A/B assignment
// - progressive recommendations + predictive prefetch hook
// - experience buffer with prediction/reward/error
// - model versioning + Big Beast sync contracts
// - privacy-aware local differential-privacy helper
// - federated-update payload helper
//
// Deliberate boundary:
// The phone cannot magically infer arbitrary app-domain semantics. The app
// still calls semantic methods for content/card/video/search actions. Global
// vector databases, Transformer/BERT training, two-tower training, multi-modal
// encoders, RL training, global stream processing, cross-user segmentation,
// global fairness audit, and secure federated aggregation belong on the Big
// Beast/backend. This file exposes the client-side contracts needed by them.
// ============================================================================

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'beast_context.dart';
import 'beast_forgetting.dart';

// ============================================================================
// ENUMS
// ============================================================================

enum BeastConsent { notDetermined, granted, denied }

enum BeastPrivacy { minimal, standard, extensive }

enum BeastStrategy {
  personalized,
  sessionBased,
  collaborative,
  contentBased,
  trending,
  popular,
  coldStart,
  exploration,
  social,
  timeAware,
  knowledgeGraph,
  bundle,
}

enum BeastEventType {
  sessionStart,
  sessionEnd,
  appForeground,
  appBackground,
  appInactive,
  appHidden,
  screenView,
  screenExit,
  buttonClick,
  scroll,
  touchSummary,
  contentImpression,
  contentOpen,
  contentDuration,
  contentReaction,
  contentSkip,
  contentHide,
  follow,
  vote,
  replyCreated,
  search,
  commentCreated,
  share,
  notificationOpen,
  networkChange,
  performance,
  error,
  recommendationRequest,
  recommendationServed,
  recommendationFeedback,
  preferenceChanged,
  experimentAssignment,
  modelSync,
  prefetch,
}

// ============================================================================
// CONFIG
// ============================================================================

class BeastConfig {
  final String serverUrl;
  final Duration flushInterval;
  final Duration requestTimeout;
  final Duration sessionTimeout;
  final Duration modelSyncInterval;
  final int batchSize;
  final int maxEvents;
  final int maxExperiences;
  final int maxRecentEvents;
  final int maxCacheEntries;
  final int embeddingDimension;
  final int retainedSyncedExperiences;
  final double explorationRate;
  final double learningRate;
  final double mmrLambda;
  final BeastPrivacy privacy;
  final bool autoRoutes;
  final bool autoLifecycle;
  final bool autoNetwork;
  final bool autoPerformance;
  final bool autoCrashTracking;
  final bool autoTouchSummary;
  final bool allowTouchCoordinates;
  final bool enableNotifications;
  final bool enableGzip;
  final Duration recommendationCacheTtl;

  const BeastConfig({
    this.serverUrl = 'https://your-app.up.railway.app',
    this.flushInterval = const Duration(seconds: 12),
    this.requestTimeout = const Duration(seconds: 6),
    this.sessionTimeout = const Duration(minutes: 30),
    this.modelSyncInterval = const Duration(minutes: 30),
    this.batchSize = 100,
    this.maxEvents = 10000,
    this.maxExperiences = 5000,
    this.maxRecentEvents = 200,
    this.maxCacheEntries = 80,
    this.embeddingDimension = 32,
    this.retainedSyncedExperiences = 500,
    this.explorationRate = 0.15,
    this.learningRate = 0.025,
    this.mmrLambda = 0.72,
    this.privacy = BeastPrivacy.standard,
    this.autoRoutes = true,
    this.autoLifecycle = true,
    this.autoNetwork = true,
    this.autoPerformance = true,
    this.autoCrashTracking = true,
    this.autoTouchSummary = false,
    this.allowTouchCoordinates = false,
    this.enableNotifications = true,
    this.enableGzip = true,
    this.recommendationCacheTtl = const Duration(minutes: 3),
  });
}

// ============================================================================
// MODELS
// ============================================================================

class BeastCandidate {
  final String itemId;
  final List<String> tags;
  final String? category;
  final String? creatorId;
  final List<String> relatedItems;
  final List<String> socialSignals;
  final Map<String, double> features;
  final Map<String, dynamic> metadata;
  final List<double>? embedding;

  const BeastCandidate({
    required this.itemId,
    this.tags = const [],
    this.category,
    this.creatorId,
    this.relatedItems = const [],
    this.socialSignals = const [],
    this.features = const {},
    this.metadata = const {},
    this.embedding,
  });
}

class BeastRecommendation {
  final String itemId;
  final double score;
  final double confidence;
  final BeastStrategy strategy;
  final String source;
  final String? reason;
  final List<String> explanationSignals;
  final Map<String, double> signals;
  final Map<String, dynamic> metadata;

  const BeastRecommendation({
    required this.itemId,
    required this.score,
    required this.confidence,
    required this.strategy,
    required this.source,
    this.reason,
    this.explanationSignals = const [],
    this.signals = const {},
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'item_id': itemId,
        'score': score,
        'confidence': confidence,
        'strategy': strategy.name,
        'source': source,
        'reason': reason,
        'explanation_signals': explanationSignals,
        'signals': signals,
        'metadata': metadata,
      };
}

class BeastModelUpdate {
  final String modelVersion;
  final Map<String, double> featureWeights;
  final Map<String, double> userPriors;
  final double learningRate;
  final double explorationRate;
  final Map<String, dynamic> banditState;
  final Map<String, dynamic> policy;

  const BeastModelUpdate({
    required this.modelVersion,
    this.featureWeights = const {},
    this.userPriors = const {},
    this.learningRate = 0.025,
    this.explorationRate = 0.15,
    this.banditState = const {},
    this.policy = const {},
  });

  factory BeastModelUpdate.fromJson(Map<String, dynamic> json) {
    Map<String, double> asDoubleMap(dynamic value) {
      if (value is! Map) return {};
      return value.map((key, raw) => MapEntry(
            key.toString(),
            raw is num ? raw.toDouble() : 0.0,
          ));
    }

    return BeastModelUpdate(
      modelVersion: json['model_version']?.toString() ?? 'edge-0',
      featureWeights: asDoubleMap(json['feature_weights'] ?? json['weights']),
      userPriors: asDoubleMap(json['user_priors']),
      learningRate: (json['learning_rate'] as num?)?.toDouble() ?? 0.025,
      explorationRate: (json['exploration_rate'] as num?)?.toDouble() ?? 0.15,
      banditState: json['bandit'] is Map
          ? Map<String, dynamic>.from(json['bandit'])
          : const {},
      policy: json['policy'] is Map
          ? Map<String, dynamic>.from(json['policy'])
          : const {},
    );
  }
}

class BeastUserSegment {
  final String id;
  final double confidence;
  final Map<String, double> signals;

  const BeastUserSegment({
    required this.id,
    required this.confidence,
    this.signals = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'confidence': confidence,
        'signals': signals,
      };
}

// ============================================================================
// USER CONTROLS
// ============================================================================

class BeastUserPreferences {
  final Map<String, double> topicBoost = {};
  final Map<String, double> topicBlock = {};
  final Map<String, double> creatorBoost = {};
  final Map<String, double> creatorBlock = {};
  final Map<String, double> itemAdjustments = {};
  final Set<String> hiddenItems = {};

  double explorationLevel = 0.15;
  double noveltyPreference = 0.5;
  double diversityPreference = 0.5;

  bool isHidden(String itemId) => hiddenItems.contains(itemId);

  double topicAdjustment(String topic) =>
      (topicBoost[_norm(topic)] ?? 0) - (topicBlock[_norm(topic)] ?? 0);

  double creatorAdjustment(String creatorId) =>
      (creatorBoost[_norm(creatorId)] ?? 0) - (creatorBlock[_norm(creatorId)] ?? 0);

  double itemAdjustment(String itemId) => itemAdjustments[itemId] ?? 0;

  Map<String, dynamic> toJson() => {
        'topic_boost': topicBoost,
        'topic_block': topicBlock,
        'creator_boost': creatorBoost,
        'creator_block': creatorBlock,
        'item_adjustments': itemAdjustments,
        'hidden_items': hiddenItems.toList(),
        'exploration_level': explorationLevel,
        'novelty_preference': noveltyPreference,
        'diversity_preference': diversityPreference,
      };

  void clear() {
    topicBoost.clear();
    topicBlock.clear();
    creatorBoost.clear();
    creatorBlock.clear();
    itemAdjustments.clear();
    hiddenItems.clear();
    explorationLevel = 0.15;
    noveltyPreference = 0.5;
    diversityPreference = 0.5;
  }

  static String _norm(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
}

// ============================================================================
// LOCAL BRAIN
// ============================================================================

class BeastBrain {
  final Map<String, double> interests = {};
  final Map<String, double> dislikes = {};
  final Map<String, double> creatorAffinity = {};
  final Map<String, double> categoryAffinity = {};
  final Map<String, double> itemAffinity = {};

  final Map<String, int> impressions = {};
  final Map<String, int> opens = {};
  final Map<String, int> skips = {};
  final Map<String, int> hides = {};
  final Map<String, int> lastSeenAt = {};

  final Map<String, Map<String, int>> transitions = {};

  final Map<String, double> ftrlZ = {};
  final Map<String, double> ftrlN = {};

  final Map<String, double> sessionInterests = {};
  final Map<String, double> sessionDislikes = {};

  final Queue<_BrainEvent> recent = Queue();

  final int maxRecent;

  static const double ftrlAlpha = 0.10;
  static const double ftrlBeta = 1.00;
  static const double ftrlLambda1 = 0.001;
  static const double ftrlLambda2 = 0.001;

  BeastBrain({this.maxRecent = 200});

  void ingest({
    required String itemId,
    required String eventType,
    List<String> tags = const [],
    String? category,
    String? creatorId,
    double reward = 0,
    int? timestamp,
  }) {
    final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;

    final previous = recent.isEmpty ? null : recent.last;

    recent.addLast(
      _BrainEvent(
        itemId: itemId,
        type: eventType,
        tags: List<String>.from(tags),
        ts: ts,
      ),
    );
    while (recent.length > maxRecent) {
      recent.removeFirst();
    }

    if (previous != null &&
        previous.itemId.isNotEmpty &&
        itemId.isNotEmpty &&
        previous.itemId != itemId) {
      final next = transitions.putIfAbsent(previous.itemId, () => {});
      next[itemId] = (next[itemId] ?? 0) + 1;
    }

    if (itemId.isNotEmpty) {
      lastSeenAt[itemId] = ts;
    }

    if (eventType == 'impression') {
      impressions[itemId] = (impressions[itemId] ?? 0) + 1;
    }
    if (eventType == 'open' || eventType == 'click') {
      opens[itemId] = (opens[itemId] ?? 0) + 1;
    }
    if (eventType == 'skip') {
      skips[itemId] = (skips[itemId] ?? 0) + 1;
    }
    if (eventType == 'hide') {
      hides[itemId] = (hides[itemId] ?? 0) + 1;
    }

    if (itemId.isNotEmpty && reward != 0) {
      itemAffinity[itemId] = (itemAffinity[itemId] ?? 0) * 0.995 + reward;
    }

    if (category != null && category.trim().isNotEmpty && reward != 0) {
      final key = _norm(category);
      categoryAffinity[key] = (categoryAffinity[key] ?? 0) + reward;
    }

    if (creatorId != null && creatorId.trim().isNotEmpty && reward != 0) {
      final key = _norm(creatorId);
      creatorAffinity[key] = (creatorAffinity[key] ?? 0) + reward;
    }

    if (tags.isEmpty || reward == 0) return;

    final target = reward >= 0 ? 1.0 : 0.0;
    final perTag = reward / max(1, tags.length);
    final sessionPerTag = reward * 1.25 / max(1, tags.length);

    final features = <String, double>{};
    for (final raw in tags) {
      final tag = _norm(raw);
      if (tag.isEmpty) continue;
      features['tag:$tag'] = 1;
      if (reward >= 0) {
        interests[tag] = (interests[tag] ?? 0) + perTag;
        sessionInterests[tag] = (sessionInterests[tag] ?? 0) + sessionPerTag;
      } else {
        dislikes[tag] = (dislikes[tag] ?? 0) + perTag.abs();
        sessionDislikes[tag] = (sessionDislikes[tag] ?? 0) + sessionPerTag.abs();
      }
    }

    _updateFtrl(features, target: target);
  }

  void _updateFtrl(
    Map<String, double> features, {
    required double target,
  }) {
    for (final entry in features.entries) {
      final x = entry.value;
      final oldZ = ftrlZ[entry.key] ?? 0;
      final oldN = ftrlN[entry.key] ?? 0;
      final prediction = predictFeature(entry.key);
      final gradient = (prediction - target) * x;
      final sigma =
          (sqrt(oldN + x * x) - sqrt(oldN)) / ftrlAlpha;

      ftrlZ[entry.key] =
          oldZ + gradient - sigma * currentWeight(entry.key);
      ftrlN[entry.key] = oldN + x * x;
    }
  }

  double currentWeight(String feature) {
    final z = ftrlZ[feature] ?? 0;
    final n = ftrlN[feature] ?? 0;
    final magnitude = max(0.0, z.abs() - ftrlLambda1);
    if (magnitude == 0) return 0;
    final sign = z < 0 ? -1.0 : 1.0;
    return -sign * magnitude /
        ((ftrlBeta + sqrt(n)) / ftrlAlpha + ftrlLambda2);
  }

  double predictFeature(String feature) =>
      _sigmoid(currentWeight(feature));

  Map<String, double> ftrlWeights() => {
        for (final key in ftrlZ.keys)
          key: currentWeight(key),
      };

  double predictTags(List<String> tags) {
    if (tags.isEmpty) return 0;
    var score = 0.0;
    for (final tag in tags) {
      score += currentWeight('tag:${_norm(tag)}');
    }
    return _sigmoid(score);
  }

  void applySessionDecay() {
    _decay(interests, 0.965);
    _decay(dislikes, 0.965);
    _decay(creatorAffinity, 0.970);
    _decay(categoryAffinity, 0.970);
    _decay(itemAffinity, 0.970);
    _decay(sessionInterests, 0.90);
    _decay(sessionDislikes, 0.90);

    _prune(interests);
    _prune(dislikes);
    _prune(creatorAffinity);
    _prune(categoryAffinity);
    _prune(itemAffinity);
    _prune(sessionInterests);
    _prune(sessionDislikes);
  }

  double tagAffinity(
    List<String> tags, {
    bool includeSession = true,
  }) {
    if (tags.isEmpty) return 0;
    var value = 0.0;
    for (final raw in tags) {
      final tag = _norm(raw);
      final longTerm = (interests[tag] ?? 0) - (dislikes[tag] ?? 0);
      final session =
          (sessionInterests[tag] ?? 0) - (sessionDislikes[tag] ?? 0);
      value += includeSession ? longTerm + session * 1.35 : longTerm;
    }
    return value / max(1, tags.length);
  }

  double categoryScore(String? category) =>
      category == null ? 0 : categoryAffinity[_norm(category)] ?? 0;

  double creatorScore(String? creatorId) =>
      creatorId == null ? 0 : creatorAffinity[_norm(creatorId)] ?? 0;

  double itemScore(String itemId) => itemAffinity[itemId] ?? 0;

  double ctr(String itemId) {
    final imp = impressions[itemId] ?? 0;
    if (imp <= 0) return 0;
    return (opens[itemId] ?? 0) / imp;
  }

  double skipRate(String itemId) {
    final imp = impressions[itemId] ?? 0;
    if (imp <= 0) return 0;
    return (skips[itemId] ?? 0) / imp;
  }

  double recency(String itemId) {
    final last = lastSeenAt[itemId];
    if (last == null) return 0;
    final ageHours =
        max(0, DateTime.now().millisecondsSinceEpoch - last) /
            Duration.millisecondsPerHour;
    return exp(-ageHours / 48.0);
  }

  double exposurePenalty(String itemId) =>
      min(0.60, (impressions[itemId] ?? 0) * 0.009);

  List<String> topTopics(int limit) {
    final entries = interests.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList();
  }

  List<String> predictNextItems(
    String currentItem,
    int limit,
  ) {
    final next = transitions[currentItem];
    if (next == null || next.isEmpty) return [];
    final entries = next.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList();
  }

  double sequenceScore(String itemId) {
    if (recent.isEmpty) return 0;
    final current = recent.last.itemId;
    if (current.isEmpty) return 0;
    final next = transitions[current];
    if (next == null || next.isEmpty) return 0;
    final total = next.values.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return 0;
    return (next[itemId] ?? 0) / total;
  }

  double sessionMomentum() {
    if (recent.isEmpty) return 0;
    var pos = 0.0;
    var neg = 0.0;
    for (final event in recent.toList().reversed.take(16)) {
      switch (event.type) {
        case 'open':
        case 'click':
        case 'positive':
        case 'share':
          pos++;
          break;
        case 'negative':
        case 'skip':
        case 'hide':
          neg++;
          break;
      }
    }
    return ((pos - neg) / max(1.0, pos + neg)).clamp(-1.0, 1.0).toDouble();
  }

  List<double> sessionEmbedding(int dimension) {
    final vector = List<double>.filled(dimension, 0);
    if (recent.isEmpty) return vector;
    final now = DateTime.now().millisecondsSinceEpoch;
    var total = 0.0;

    for (final event in recent.toList().reversed.take(40)) {
      final ageMinutes =
          max(0, now - event.ts) / Duration.millisecondsPerMinute;
      final decay = exp(-ageMinutes / 15.0);
      final eventWeight = _eventWeight(event.type);
      final itemVector = _hashEmbedding(event.itemId, dimension);
      final weight = decay * eventWeight;
      total += weight.abs();
      for (var i = 0; i < dimension; i++) {
        vector[i] += itemVector[i] * weight;
      }
    }

    if (total > 0) {
      for (var i = 0; i < dimension; i++) {
        vector[i] /= total;
      }
    }

    return vector;
  }

  Map<String, dynamic> snapshot() => {
        'top_topics': topTopics(20),
        'interest': _topMap(interests, 30),
        'dislike': _topMap(dislikes, 15),
        'category_affinity': _topMap(categoryAffinity, 20),
        'creator_affinity': _topMap(creatorAffinity, 20),
        'recent_items': recent.toList().reversed
            .take(30)
            .map((e) => e.itemId)
            .where((e) => e.isNotEmpty)
            .toList(),
        'recent_events': recent.toList().reversed
            .take(30)
            .map((e) => e.type)
            .toList(),
        'next_item_hints': recent.isEmpty
            ? const []
            : predictNextItems(recent.last.itemId, 10),
        'session_momentum': sessionMomentum(),
        'ftrl_feature_count': ftrlZ.length,
      };

  /// Full serializable state for the persistent user brain.
  Map<String, dynamic> exportState() => {
        'interests': interests,
        'dislikes': dislikes,
        'creator_affinity': creatorAffinity,
        'category_affinity': categoryAffinity,
        'item_affinity': itemAffinity,
        'impressions': impressions,
        'opens': opens,
        'skips': skips,
        'hides': hides,
        'last_seen_at': lastSeenAt,
        'transitions': transitions,
        'ftrl_z': ftrlZ,
        'ftrl_n': ftrlN,
        'session_interests': sessionInterests,
        'session_dislikes': sessionDislikes,
        'recent': recent
            .map((e) => {
                  'item_id': e.itemId,
                  'type': e.type,
                  'tags': e.tags,
                  'ts': e.ts,
                })
            .toList(),
      };

  void importState(Map<String, dynamic> state) {
    clear();
    _restoreDoubleMap(interests, state['interests']);
    _restoreDoubleMap(dislikes, state['dislikes']);
    _restoreDoubleMap(creatorAffinity, state['creator_affinity']);
    _restoreDoubleMap(categoryAffinity, state['category_affinity']);
    _restoreDoubleMap(itemAffinity, state['item_affinity']);
    _restoreIntMap(impressions, state['impressions']);
    _restoreIntMap(opens, state['opens']);
    _restoreIntMap(skips, state['skips']);
    _restoreIntMap(hides, state['hides']);
    _restoreIntMap(lastSeenAt, state['last_seen_at']);
    _restoreTransitions(transitions, state['transitions']);
    _restoreDoubleMap(ftrlZ, state['ftrl_z']);
    _restoreDoubleMap(ftrlN, state['ftrl_n']);
    _restoreDoubleMap(sessionInterests, state['session_interests']);
    _restoreDoubleMap(sessionDislikes, state['session_dislikes']);

    final rawRecent = state['recent'];
    if (rawRecent is List) {
      for (final raw in rawRecent) {
        if (raw is! Map) continue;
        final itemId = raw['item_id']?.toString() ?? '';
        final type = raw['type']?.toString() ?? '';
        final ts = raw['ts'] is num ? (raw['ts'] as num).toInt() : 0;
        final tags = raw['tags'] is List
            ? (raw['tags'] as List).map((e) => e.toString()).toList()
            : const <String>[];
        recent.addLast(_BrainEvent(
          itemId: itemId,
          type: type,
          tags: tags,
          ts: ts,
        ));
      }
      while (recent.length > maxRecent) {
        recent.removeFirst();
      }
    }
  }

  void _restoreDoubleMap(Map<String, double> target, Object? raw) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is num && value.toDouble().isFinite) {
        target[entry.key.toString()] = value.toDouble();
      }
    }
  }

  void _restoreIntMap(Map<String, int> target, Object? raw) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is num) {
        target[entry.key.toString()] = value.toInt();
      }
    }
  }

  void _restoreTransitions(
    Map<String, Map<String, int>> target,
    Object? raw,
  ) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final inner = <String, int>{};
      for (final next in (entry.value as Map).entries) {
        final value = next.value;
        if (value is num && value.toInt() > 0) {
          inner[next.key.toString()] = value.toInt();
        }
      }
      if (inner.isNotEmpty) {
        target[entry.key.toString()] = inner;
      }
    }
  }

  void clear() {
    interests.clear();
    dislikes.clear();
    creatorAffinity.clear();
    categoryAffinity.clear();
    itemAffinity.clear();
    impressions.clear();
    opens.clear();
    skips.clear();
    hides.clear();
    lastSeenAt.clear();
    transitions.clear();
    ftrlZ.clear();
    ftrlN.clear();
    sessionInterests.clear();
    sessionDislikes.clear();
    recent.clear();
  }

  Map<String, double> _topMap(
    Map<String, double> source,
    int limit,
  ) {
    final entries = source.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries.take(limit));
  }

  void _decay(Map<String, double> map, double factor) {
    map.updateAll((_, value) => value * factor);
  }

  void _prune(Map<String, double> map) {
    final dead = map.entries
        .where((e) => e.value.abs() < 0.05)
        .map((e) => e.key)
        .toList();
    for (final key in dead) {
      map.remove(key);
    }
  }

  static double _eventWeight(String type) {
    switch (type) {
      case 'open':
      case 'click':
        return 2.0;
      case 'dwell':
        return 1.7;
      case 'positive':
        return 4.0;
      case 'share':
        return 5.0;
      case 'negative':
        return -3.0;
      case 'skip':
        return -1.3;
      case 'hide':
        return -4.0;
      default:
        return 0.2;
    }
  }

  static List<double> _hashEmbedding(String text, int dim) {
    final random = Random(_stableHash(text));
    return List<double>.generate(dim, (_) => random.nextDouble() * 2 - 1);
  }

  static int _stableHash(String text) {
    var hash = 2166136261;
    for (final code in text.codeUnits) {
      hash ^= code;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  static String _norm(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  static double _sigmoid(double x) {
    if (x >= 0) {
      final z = exp(-x);
      return 1 / (1 + z);
    }
    final z = exp(x);
    return z / (1 + z);
  }
}

class _BrainEvent {
  final String itemId;
  final String type;
  final List<String> tags;
  final int ts;

  const _BrainEvent({
    required this.itemId,
    required this.type,
    required this.tags,
    required this.ts,
  });
}

// ============================================================================
// THOMPSON SAMPLING
// ============================================================================

class BeastThompsonBandit {
  final Map<String, _BetaArm> _arms = {};
  final Random _rng = Random.secure();

  double sample(String arm) {
    final state = _arms.putIfAbsent(
      arm,
      () => _BetaArm(alpha: 1, beta: 1),
    );
    final x = _gamma(state.alpha);
    final y = _gamma(state.beta);
    final sum = x + y;
    return sum <= 0 ? 0.5 : x / sum;
  }

  void update(String arm, double reward) {
    final state = _arms.putIfAbsent(
      arm,
      () => _BetaArm(alpha: 1, beta: 1),
    );
    final r = reward.clamp(-1.0, 1.0).toDouble();
    if (r >= 0) {
      state.alpha += r + 0.01;
    } else {
      state.beta += r.abs() + 0.01;
    }
  }

  Map<String, dynamic> exportState() => {
        for (final e in _arms.entries)
          e.key: {
            'alpha': e.value.alpha,
            'beta': e.value.beta,
          },
      };

  void importState(Map<String, dynamic> state) {
    _arms.clear();
    for (final entry in state.entries) {
      final raw = entry.value;
      if (raw is! Map) continue;
      _arms[entry.key] = _BetaArm(
        alpha: (raw['alpha'] as num?)?.toDouble() ?? 1,
        beta: (raw['beta'] as num?)?.toDouble() ?? 1,
      );
    }
  }

  double _gamma(double shape) {
    if (shape < 1) {
      return _gamma(shape + 1) * pow(_rng.nextDouble(), 1 / shape);
    }
    final d = shape - 1 / 3;
    final c = 1 / sqrt(9 * d);
    while (true) {
      final x = _normal();
      final v0 = 1 + c * x;
      if (v0 <= 0) continue;
      final v = v0 * v0 * v0;
      final u = _rng.nextDouble();
      if (u < 1 - 0.0331 * pow(x, 4)) return d * v;
      if (log(u) < 0.5 * x * x + d * (1 - v + log(v))) {
        return d * v;
      }
    }
  }

  double _normal() {
    var u1 = _rng.nextDouble();
    var u2 = _rng.nextDouble();
    if (u1 <= 0) u1 = 1e-12;
    if (u2 <= 0) u2 = 1e-12;
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }
}

class _BetaArm {
  double alpha;
  double beta;

  _BetaArm({required this.alpha, required this.beta});
}

// ============================================================================
// DIAGONAL LINUCB
// ============================================================================

class BeastLinUcb {
  final int dimensions;
  double alpha;
  final Map<String, List<double>> _aDiag = {};
  final Map<String, List<double>> _b = {};

  BeastLinUcb({this.dimensions = 32, this.alpha = 0.35});

  double score(String itemId, List<double> x) {
    final a = _ensure(_aDiag, itemId, 1.0);
    final b = _ensure(_b, itemId, 0.0);
    final vector = _normalize(x);
    var mean = 0.0;
    var variance = 0.0;

    for (var i = 0; i < dimensions; i++) {
      final theta = b[i] / max(1e-6, a[i]);
      mean += theta * vector[i];
      variance += (vector[i] * vector[i]) / max(1e-6, a[i]);
    }

    return mean + alpha * sqrt(max(0, variance));
  }

  void update(String itemId, List<double> x, double reward) {
    final a = _ensure(_aDiag, itemId, 1.0);
    final b = _ensure(_b, itemId, 0.0);
    final vector = _normalize(x);
    final r = reward.clamp(-1.0, 1.0).toDouble();

    for (var i = 0; i < dimensions; i++) {
      a[i] += vector[i] * vector[i];
      b[i] += vector[i] * r;
    }
  }

  Map<String, dynamic> exportState() => {
        'dimensions': dimensions,
        'alpha': alpha,
        'a_diag': _aDiag,
        'b': _b,
      };

  void importState(Map<String, dynamic> state) {
    _aDiag.clear();
    _b.clear();
    if (state['alpha'] is num) {
      alpha = (state['alpha'] as num).toDouble();
    }
    final rawA = state['a_diag'];
    if (rawA is Map) {
      for (final entry in rawA.entries) {
        if (entry.value is List) {
          _aDiag[entry.key.toString()] = (entry.value as List)
              .map((x) => (x as num).toDouble())
              .take(dimensions)
              .toList();
          _pad(_aDiag[entry.key.toString()]!, 1.0);
        }
      }
    }
    final rawB = state['b'];
    if (rawB is Map) {
      for (final entry in rawB.entries) {
        if (entry.value is List) {
          _b[entry.key.toString()] = (entry.value as List)
              .map((x) => (x as num).toDouble())
              .take(dimensions)
              .toList();
          _pad(_b[entry.key.toString()]!, 0.0);
        }
      }
    }
  }

  List<double> _ensure(
    Map<String, List<double>> map,
    String key,
    double fill,
  ) => map.putIfAbsent(
        key,
        () => List<double>.filled(dimensions, fill),
      );

  void _pad(List<double> list, double fill) {
    while (list.length < dimensions) {
      list.add(fill);
    }
  }

  List<double> _normalize(List<double> input) {
    final out = List<double>.filled(dimensions, 0);
    for (var i = 0; i < min(dimensions, input.length); i++) {
      out[i] = input[i].clamp(-1.0, 1.0).toDouble();
    }
    var norm = 0.0;
    for (final x in out) {
      norm += x * x;
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (var i = 0; i < out.length; i++) {
        out[i] /= norm;
      }
    }
    return out;
  }
}

// ============================================================================
// RANKING
// ============================================================================

class BeastObjectiveWeights {
  final double relevance;
  final double watchTime;
  final double quality;
  final double novelty;
  final double diversity;
  final double social;
  final double business;

  const BeastObjectiveWeights({
    this.relevance = 0.34,
    this.watchTime = 0.18,
    this.quality = 0.14,
    this.novelty = 0.10,
    this.diversity = 0.10,
    this.social = 0.08,
    this.business = 0.06,
  });
}

class BeastRanker {
  final BeastObjectiveWeights weights;

  const BeastRanker({this.weights = const BeastObjectiveWeights()});

  double score({
    required double relevance,
    required double watchTime,
    required double quality,
    required double novelty,
    required double diversity,
    required double social,
    required double business,
  }) {
    return weights.relevance * relevance +
        weights.watchTime * watchTime +
        weights.quality * quality +
        weights.novelty * novelty +
        weights.diversity * diversity +
        weights.social * social +
        weights.business * business;
  }
}

class _CandidateSignals {
  final double relevance;
  final double preference;
  final double category;
  final double creator;
  final double item;
  final double ctr;
  final double skipRate;
  final double exposure;
  final double recency;
  final double sequence;
  final double time;
  final double novelty;
  final double social;
  final double quality;
  final double business;
  final double session;
  final double prediction;
  final bool sessionIntent;

  const _CandidateSignals({
    required this.relevance,
    required this.preference,
    required this.category,
    required this.creator,
    required this.item,
    required this.ctr,
    required this.skipRate,
    required this.exposure,
    required this.recency,
    required this.sequence,
    required this.time,
    required this.novelty,
    required this.social,
    required this.quality,
    required this.business,
    required this.session,
    required this.prediction,
    required this.sessionIntent,
  });
}

// ============================================================================
// MAIN ENGINE
// ============================================================================

class BeastUltimate {
  static final BeastUltimate _instance = BeastUltimate._internal();
  factory BeastUltimate() => _instance;
  BeastUltimate._internal();

  final BeastBrain brain = BeastBrain();
  final BeastThompsonBandit thompson = BeastThompsonBandit();
  final BeastUserPreferences preferences = BeastUserPreferences();

  /// Advanced context / mood layer.
  final BeastContextEngine contextEngine = BeastContextEngine();

  /// Adaptive long-term memory decay.
  final BeastAdaptiveForgetting forgetting = BeastAdaptiveForgetting();

  BeastLinUcb? _linUcb;
  BeastRanker _ranker = const BeastRanker();

  final LinkedHashMap<String, _RecommendationCacheEntry> _cache = LinkedHashMap();
  final StreamController<Map<String, dynamic>> _eventStream = StreamController.broadcast();

  final Map<String, _BeastExperiment> _experiments = {};

  BeastConfig _config = const BeastConfig();
  Database? _db;
  http.Client? _http;
  FlutterLocalNotificationsPlugin? _notifications;
  StreamSubscription? _networkSub;
  Timer? _flushTimer;
  Timer? _modelTimer;

  BeastConsent _consent = BeastConsent.notDetermined;
  bool _ready = false;
  bool _disposed = false;
  bool _flushRunning = false;
  bool _syncRunning = false;
  bool _modelSyncRunning = false;

  String _userId = 'anonymous';
  String _sessionId = '';
  String _screen = 'unknown';
  String _modelVersion = 'edge-0';

  double _explorationRate = 0.15;
  double _learningRate = 0.025;

  int _sessionStartedAt = 0;
  int _screenStartedAt = 0;
  int _lastActivityAt = 0;

  ConnectivityResult _network = ConnectivityResult.none;

  DateTime? _lastFrameAt;
  int _frameCount = 0;
  int _jankFrames = 0;
  double _frameTimeEmaMs = 16.67;

  int _touchCount = 0;
  double _touchTravel = 0;
  Offset? _lastTouch;

  BeastConsent get consent => _consent;
  bool get ready => _ready;
  bool get analyticsEnabled => _consent == BeastConsent.granted;
  String get userId => _userId;
  String get sessionId => _sessionId;
  String get currentScreen => _screen;
  String get modelVersion => _modelVersion;
  Stream<Map<String, dynamic>> get eventStream => _eventStream.stream;

  // --------------------------------------------------------------------------
  // INIT
  // --------------------------------------------------------------------------

  Future<void> init({
    required String userId,
    BeastConfig? config,
  }) async {
    if (_disposed) {
      _disposed = false;
    }
    if (_ready) {
      if (_userId != userId.trim() && userId.trim().isNotEmpty) {
        await switchUser(userId);
      }
      return;
    }

    _config = config ?? _config;
    _userId = userId.trim().isEmpty ? 'anonymous' : userId.trim();
    _http = http.Client();
    _linUcb = BeastLinUcb(dimensions: _config.embeddingDimension);
    _ranker = const BeastRanker();

    await _openDatabase();
    await _loadPersistentState();

    final now = DateTime.now().millisecondsSinceEpoch;
    _sessionId = _id();
    _sessionStartedAt = now;
    _screenStartedAt = now;
    _lastActivityAt = now;
    _ready = true;

    if (_config.autoNetwork) await _initNetwork();
    if (_config.autoLifecycle) {
      WidgetsBinding.instance.addObserver(_LifecycleObserver(this));
    }
    if (_config.autoPerformance) _startPerformanceMonitor();
    if (_config.autoTouchSummary) _attachTouchTracking();
    if (_config.enableNotifications) await _initNotifications();
    if (_config.autoCrashTracking) _installCrashTracking();

    _flushTimer = Timer.periodic(
      _config.flushInterval,
      (_) => unawaited(flush()),
    );

    _modelTimer = Timer.periodic(
      _config.modelSyncInterval,
      (_) => unawaited(syncModel()),
    );

    if (analyticsEnabled) {
      brain.applySessionDecay();
      await _writeEvent(
        BeastEventType.sessionStart,
        {
          'session_id': _sessionId,
          'model_version': _modelVersion,
        },
        priority: 3,
      );
      await syncModel();
    }
  }

  NavigatorObserver get navigatorObserver => BeastNavigatorObserver(this);

  // --------------------------------------------------------------------------
  // USER SWITCH
  // --------------------------------------------------------------------------

  Future<void> switchUser(String userId) async {
    final nextUser = userId.trim();
    if (nextUser.isEmpty || nextUser == _userId) return;

    if (_ready && analyticsEnabled) {
      try {
        await _persistLearningState();
        await _writeEvent(
          BeastEventType.sessionEnd,
          {'reason': 'user_switch', 'session_age_ms': _sessionAgeMs()},
          priority: 3,
        );
        await flushTouchSummary();
        await syncExperiences();
        await flush();
      } catch (e) {
        debugPrint('Beast user-switch persistence failed: $e');
      }
    }

    _cache.clear();
    brain.clear();
    preferences.clear();
    thompson.importState(const <String, dynamic>{});
    _linUcb = BeastLinUcb(dimensions: _config.embeddingDimension);

    _userId = nextUser;
    _sessionId = _id();
    final now = DateTime.now().millisecondsSinceEpoch;
    _sessionStartedAt = now;
    _screenStartedAt = now;
    _lastActivityAt = now;

    await _loadPersistentState();

    if (_allowed()) {
      await _writeEvent(
        BeastEventType.sessionStart,
        {'session_id': _sessionId, 'reason': 'user_switch'},
        priority: 3,
      );
    }
  }

  // --------------------------------------------------------------------------
  // CONSENT
  // --------------------------------------------------------------------------

  Future<void> setConsent(BeastConsent value) async {
    if (!_ready) return;

    _consent = value;
    await _saveMeta('consent', value.name);

    if (value == BeastConsent.granted) {
      brain.applySessionDecay();
      await _writeEvent(
        BeastEventType.sessionStart,
        {'session_id': _sessionId, 'model_version': _modelVersion},
        priority: 3,
      );
      await syncModel();
    } else {
      await _eraseBehavior();
    }
  }

  // --------------------------------------------------------------------------
  // SCREEN / APP
  // --------------------------------------------------------------------------

  Future<void> screen(String name) async {
    if (!_allowed()) return;
    final next = name.trim();
    if (next.isEmpty || next == _screen) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_screenStartedAt > 0) {
      await _writeEvent(
        BeastEventType.screenExit,
        {
          'screen': _screen,
          'duration_ms': max(0, now - _screenStartedAt),
        },
      );
    }

    _screen = next;
    _screenStartedAt = now;
    _lastActivityAt = now;
    _cache.clear();

    await _writeEvent(
      BeastEventType.screenView,
      {'screen': next, 'session_age_ms': _sessionAgeMs()},
    );

    await _ensureSession();
  }

  Future<void> onForeground() async {
    if (!_allowed()) return;
    await _ensureSession();
    await _writeEvent(BeastEventType.appForeground, {}, priority: 2);
    await syncModel();
  }

  Future<void> onBackground() async {
    if (!_allowed()) return;
    await _writeEvent(
      BeastEventType.appBackground,
      {'session_age_ms': _sessionAgeMs()},
      priority: 2,
    );
    await flushTouchSummary();
    await _persistLearningState();
    await syncExperiences();
    await flush();
  }

  Future<void> onInactive() async {
    if (!_allowed()) return;
    await _writeEvent(BeastEventType.appInactive, {}, priority: 0);
  }

  Future<void> onHidden() async {
    if (!_allowed()) return;
    await _writeEvent(BeastEventType.appHidden, {}, priority: 0);
  }

  // --------------------------------------------------------------------------
  // CONTENT SIGNALS
  // --------------------------------------------------------------------------

  void _observeContext({
    required String type,
    required String itemId,
    List<String> tags = const [],
    int? durationMs,
    double? value,
  }) {
    contextEngine.observe(
      BeastContextEvent(
        type: type,
        timestamp: DateTime.now(),
        tags: tags,
        durationMs: durationMs,
        value: value,
      ),
    );

    // Feed the adaptive forgetting layer with the same semantic evidence.
    if (value != null && value > 0) {
      forgetting.reinforce(itemId, evidence: value);
      for (final tag in tags) {
        forgetting.reinforce('tag:$tag', evidence: value * 0.35);
      }
    } else if (value != null && value < 0) {
      forgetting.penalize(itemId, evidence: value.abs());
      for (final tag in tags) {
        forgetting.penalize('tag:$tag', evidence: value.abs() * 0.35);
      }
    }
  }

  Future<void> impression({
    required String itemId,
    List<String> tags = const [],
    String? category,
    String? creatorId,
    int position = 0,
    String source = 'unknown',
  }) async {
    if (!_allowed()) return;

    _observeContext(type: 'impression', itemId: itemId, tags: tags, value: 0.02);

    brain.ingest(
      itemId: itemId,
      eventType: 'impression',
      tags: tags,
      category: category,
      creatorId: creatorId,
      reward: 0.02,
    );

    await _persistLearningState();

    await _writeEvent(
      BeastEventType.contentImpression,
      {
        'content_id': itemId,
        'tags': tags,
        'category': category,
        'creator_id': creatorId,
        'position': position,
        'source': source,
      },
    );
  }

  Future<void> openContent({
    required String itemId,
    List<String> tags = const [],
    String? category,
    String? creatorId,
    int position = 0,
    String source = 'unknown',
  }) async {
    if (!_allowed()) return;
    await _ensureSession();

    final candidate = BeastCandidate(
      itemId: itemId,
      tags: tags,
      category: category,
      creatorId: creatorId,
    );
    final prediction = _predictCandidateSignals(candidate).prediction;

    _observeContext(type: 'open', itemId: itemId, tags: tags, value: 1.2);

    brain.ingest(
      itemId: itemId,
      eventType: 'open',
      tags: tags,
      category: category,
      creatorId: creatorId,
      reward: 1.2,
    );

    thompson.update(itemId, 0.7);
    _linUcb?.update(
      itemId,
      brain.sessionEmbedding(_config.embeddingDimension),
      0.7,
    );

    await _recordExperience(
      itemId: itemId,
      eventType: 'open',
      reward: 1.0,
      prediction: prediction,
      position: position,
      explored: false,
      features: _tagVector(tags),
      context: {
        'screen': _screen,
        'source': source,
        'category': category,
        'creator_id': creatorId,
      },
    );

    await _persistLearningState();

    await _writeEvent(
      BeastEventType.contentOpen,
      {
        'content_id': itemId,
        'tags': tags,
        'category': category,
        'creator_id': creatorId,
        'position': position,
        'source': source,
      },
      priority: 2,
    );

    _cache.clear();
  }

  Future<void> duration({
    required String itemId,
    required int durationMs,
    List<String> tags = const [],
    String? category,
    String? creatorId,
  }) async {
    if (!_allowed() || durationMs <= 0) return;

    final reward = _durationReward(durationMs);
    final candidate = BeastCandidate(
      itemId: itemId,
      tags: tags,
      category: category,
      creatorId: creatorId,
    );
    final prediction = _predictCandidateSignals(candidate).prediction;

    _observeContext(type: 'duration', itemId: itemId, tags: tags, durationMs: durationMs, value: reward);

    brain.ingest(
      itemId: itemId,
      eventType: 'dwell',
      tags: tags,
      category: category,
      creatorId: creatorId,
      reward: reward * 3.0,
    );

    thompson.update(itemId, reward);
    _linUcb?.update(
      itemId,
      brain.sessionEmbedding(_config.embeddingDimension),
      reward,
    );

    await _recordExperience(
      itemId: itemId,
      eventType: 'dwell',
      reward: reward,
      prediction: prediction,
      position: 0,
      explored: false,
      features: _tagVector(tags),
      context: {
        'screen': _screen,
        'duration_ms': durationMs,
      },
    );

    await _persistLearningState();

    await _writeEvent(
      BeastEventType.contentDuration,
      {
        'content_id': itemId,
        'duration_ms': durationMs,
        'tags': tags,
      },
    );

    _cache.clear();
  }

  Future<void> reaction({
    required String itemId,
    required String reaction,
    List<String> tags = const [],
    String? category,
    String? creatorId,
  }) async {
    if (!_allowed()) return;

    final positive = {
      'like',
      'love',
      'save',
      'share',
    }.contains(reaction);

    final reward = positive ? 1.0 : -1.0;
    final candidate = BeastCandidate(
      itemId: itemId,
      tags: tags,
      category: category,
      creatorId: creatorId,
    );
    final prediction = _predictCandidateSignals(candidate).prediction;

    _observeContext(type: reaction, itemId: itemId, tags: tags, value: reward);

    brain.ingest(
      itemId: itemId,
      eventType: positive ? 'positive' : 'negative',
      tags: tags,
      category: category,
      creatorId: creatorId,
      reward: positive ? 5.0 : -6.0,
    );

    thompson.update(itemId, reward);
    _linUcb?.update(
      itemId,
      brain.sessionEmbedding(_config.embeddingDimension),
      reward,
    );

    await _recordExperience(
      itemId: itemId,
      eventType: positive ? 'positive' : 'negative',
      reward: reward,
      prediction: prediction,
      position: 0,
      explored: false,
      features: _tagVector(tags),
      context: {
        'screen': _screen,
        'reaction': reaction,
      },
    );

    await _persistLearningState();

    await _writeEvent(
      BeastEventType.contentReaction,
      {
        'content_id': itemId,
        'reaction': reaction,
        'positive': positive,
        'tags': tags,
      },
      priority: 2,
    );

    _cache.clear();
  }

  Future<void> skip(
    String itemId, {
    List<String> tags = const [],
  }) async {
    if (!_allowed()) return;

    _observeContext(type: 'skip', itemId: itemId, tags: tags, value: -0.8);

    brain.ingest(
      itemId: itemId,
      eventType: 'skip',
      tags: tags,
      reward: -0.8,
    );
    thompson.update(itemId, -0.8);

    await _recordExperience(
      itemId: itemId,
      eventType: 'skip',
      reward: -0.8,
      prediction: 0.5,
      position: 0,
      explored: false,
      features: _tagVector(tags),
      context: {'screen': _screen},
    );

    await _persistLearningState();

    await _writeEvent(
      BeastEventType.contentSkip,
      {'content_id': itemId, 'tags': tags},
    );

    _cache.clear();
  }

  Future<void> hide(
    String itemId, {
    String? reason,
  }) async {
    if (!_allowed()) return;

    preferences.hiddenItems.add(itemId);
    brain.ingest(
      itemId: itemId,
      eventType: 'hide',
      reward: -4.0,
    );

    await _persistPreferences();
    await _writeEvent(
      BeastEventType.contentHide,
      {'content_id': itemId, 'reason': reason},
      priority: 2,
    );
    _cache.clear();
  }

  Future<void> moreLikeThis(
    String itemId, {
    List<String> tags = const [],
  }) async {
    if (!_allowed()) return;
    for (final tag in tags) {
      final key = _norm(tag);
      preferences.topicBoost[key] =
          (preferences.topicBoost[key] ?? 0) + 1.0;
    }
    preferences.itemAdjustments[itemId] =
        (preferences.itemAdjustments[itemId] ?? 0) + 1.5;
    await _persistPreferences();
    await _writeEvent(
      BeastEventType.preferenceChanged,
      {'type': 'more_like_this', 'item_id': itemId, 'tags': tags},
    );
    _cache.clear();
  }

  Future<void> lessLikeThis(
    String itemId, {
    List<String> tags = const [],
  }) async {
    if (!_allowed()) return;
    for (final tag in tags) {
      final key = _norm(tag);
      preferences.topicBlock[key] =
          (preferences.topicBlock[key] ?? 0) + 1.0;
    }
    preferences.itemAdjustments[itemId] =
        (preferences.itemAdjustments[itemId] ?? 0) - 1.5;
    await _persistPreferences();
    await _writeEvent(
      BeastEventType.preferenceChanged,
      {'type': 'less_like_this', 'item_id': itemId, 'tags': tags},
    );
    _cache.clear();
  }

  Future<void> setNotInterested(String topic) async {
    if (!_allowed()) return;
    final key = _norm(topic);
    preferences.topicBlock[key] =
        (preferences.topicBlock[key] ?? 0) + 2.0;
    await _persistPreferences();
    await _writeEvent(
      BeastEventType.preferenceChanged,
      {'type': 'not_interested', 'topic': key},
    );
    _cache.clear();
  }

  Future<void> setExplorationLevel(double value) async {
    preferences.explorationLevel = value.clamp(0.0, 1.0).toDouble();
    await _persistPreferences();
  }

  Future<void> setNoveltyPreference(double value) async {
    preferences.noveltyPreference = value.clamp(0.0, 1.0).toDouble();
    await _persistPreferences();
  }

  Future<void> setDiversityPreference(double value) async {
    preferences.diversityPreference = value.clamp(0.0, 1.0).toDouble();
    await _persistPreferences();
  }

  Future<void> button(
    String name, {
    Map<String, dynamic>? extra,
  }) async {
    if (!_allowed()) return;
    await _writeEvent(
      BeastEventType.buttonClick,
      {'button': name, ..._sanitize(extra ?? {})},
    );
  }

  Future<void> search(String query, {int resultCount = 0}) async {
    if (!_allowed()) return;
    final q = query.trim();
    await _writeEvent(
      BeastEventType.search,
      {
        'query_length': q.characters.length,
        'token_count': q.isEmpty
            ? 0
            : q.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).length.clamp(0, 40).toInt(),
        'result_count': resultCount,
      },
    );
  }

  Future<void> comment({
    required String itemId,
    required String text,
    String? category,
    String? creatorId,
  }) async {
    if (!_allowed()) return;

    brain.ingest(
      itemId: itemId,
      eventType: 'comment',
      category: category,
      creatorId: creatorId,
      reward: 0.9,
    );

    await _writeEvent(
      BeastEventType.commentCreated,
      {
        'content_id': itemId,
        'text_length': text.characters.length,
        'has_text': text.trim().isNotEmpty,
        'category': category,
        'creator_id': creatorId,
      },
      priority: 2,
    );

    thompson.update(itemId, 0.9);
    await _recordExperience(
      itemId: itemId,
      eventType: 'comment',
      reward: 0.9,
      prediction: 0.5,
      position: 0,
      explored: false,
      features: const {'comment': 1.0},
      context: {'screen': _screen},
    );
  }

  /// متابعة مستخدم/منشئ محتوى.
  ///
  /// إشارة إيجابية قوية على مستوى الـcreatorAffinity، بنفس معايير
  /// reaction الإيجابية (like/love/save/share).
  Future<void> follow(
    String userId, {
    String? category,
  }) async {
    if (!_allowed()) return;

    brain.ingest(
      itemId: userId,
      eventType: 'follow',
      category: category,
      creatorId: userId,
      reward: 5.0,
    );

    thompson.update(userId, 1.0);

    await _persistLearningState();

    await _writeEvent(
      BeastEventType.follow,
      {
        'target_user_id': userId,
        'category': category,
      },
      priority: 2,
    );

    await _recordExperience(
      itemId: userId,
      eventType: 'follow',
      reward: 1.0,
      prediction: 0.5,
      position: 0,
      explored: false,
      features: const {'follow': 1.0},
      context: {'screen': _screen},
    );
  }

  /// تصويت على عنصر (استفتاء/تقييم سريع).
  ///
  /// إشارة تفاعل معتدلة الإيجابية بغض النظر عن قيمة الخيار،
  /// لأن التصويت نفسه فعل انخراط، سواء كان الخيار موافقًا أو لا.
  Future<void> vote(
    String itemId, {
    String? option,
    String? category,
    String? creatorId,
  }) async {
    if (!_allowed()) return;

    brain.ingest(
      itemId: itemId,
      eventType: 'vote',
      category: category,
      creatorId: creatorId,
      reward: 0.6,
    );

    thompson.update(itemId, 0.6);

    await _persistLearningState();

    await _writeEvent(
      BeastEventType.vote,
      {
        'content_id': itemId,
        'option': option,
        'category': category,
        'creator_id': creatorId,
      },
      priority: 1,
    );

    await _recordExperience(
      itemId: itemId,
      eventType: 'vote',
      reward: 0.6,
      prediction: 0.5,
      position: 0,
      explored: false,
      features: const {'vote': 1.0},
      context: {'screen': _screen, 'option': option},
    );
  }

  /// رد على تعليق موجود.
  ///
  /// يُعامل كإشارة انخراط قوية شبيهة بالتعليق، لكن بدون نص
  /// (النص/طوله غير متاح على مستوى هذه الواجهة).
  Future<void> reply(
    String itemId, {
    String? category,
    String? creatorId,
    String? parentCommentId,
  }) async {
    if (!_allowed()) return;

    brain.ingest(
      itemId: itemId,
      eventType: 'reply',
      category: category,
      creatorId: creatorId,
      reward: 0.7,
    );

    thompson.update(itemId, 0.7);

    await _persistLearningState();

    await _writeEvent(
      BeastEventType.replyCreated,
      {
        'content_id': itemId,
        'category': category,
        'creator_id': creatorId,
        'parent_comment_id': parentCommentId,
      },
      priority: 2,
    );

    await _recordExperience(
      itemId: itemId,
      eventType: 'reply',
      reward: 0.7,
      prediction: 0.5,
      position: 0,
      explored: false,
      features: const {'reply': 1.0},
      context: {'screen': _screen, 'parent_comment_id': parentCommentId},
    );
  }

  /// ملاحظة صريحة من المستخدم حول جودة توصية معيّنة.
  ///
  /// feedback نصّي حرّ. القيم الإيجابية/السلبية المعروفة تُترجم إلى
  /// مكافأة موجبة/سالبة؛ أي قيمة أخرى تُسجَّل بمكافأة محايدة (0)
  /// دون التأثير على bandit/brain.
  Future<void> recommendationFeedback(
    String itemId, {
    required String feedback,
  }) async {
    if (!_allowed()) return;

    const positiveFeedback = {
      'relevant',
      'good',
      'helpful',
      'more_like_this',
      'like',
    };
    const negativeFeedback = {
      'irrelevant',
      'bad',
      'not_helpful',
      'less_like_this',
      'dislike',
    };

    final normalized = feedback.trim().toLowerCase();
    final reward = positiveFeedback.contains(normalized)
        ? 0.8
        : negativeFeedback.contains(normalized)
            ? -0.8
            : 0.0;

    if (reward != 0.0) {
      brain.ingest(
        itemId: itemId,
        eventType: reward > 0 ? 'positive' : 'negative',
        reward: reward > 0 ? 5.0 : -6.0,
      );
      thompson.update(itemId, reward);
    }

    await _writeEvent(
      BeastEventType.recommendationFeedback,
      {
        'content_id': itemId,
        'feedback': feedback,
      },
      priority: 2,
    );

    await _recordExperience(
      itemId: itemId,
      eventType: 'recommendation_feedback',
      reward: reward,
      prediction: 0.5,
      position: 0,
      explored: false,
      features: const {'recommendation_feedback': 1.0},
      context: {'screen': _screen, 'feedback': feedback},
    );
  }

  Future<void> share(
    String itemId, {
    List<String> tags = const [],
  }) async {
    if (!_allowed()) return;
    thompson.update(itemId, 1.0);
    await _writeEvent(
      BeastEventType.share,
      {'content_id': itemId, 'tags': tags},
      priority: 2,
    );
  }

  Future<void> notificationOpened(String notificationId) async {
    if (!_allowed()) return;
    await _writeEvent(
      BeastEventType.notificationOpen,
      {'notification_id': notificationId},
      priority: 1,
    );
  }

  // --------------------------------------------------------------------------
  // RECOMMEND
  // --------------------------------------------------------------------------

  Future<List<BeastRecommendation>> recommend(
    List<BeastCandidate> candidates, {
    required String context,
    int limit = 20,
    bool useBigBeast = true,
    bool diversity = true,
    String? experimentName,
  }) async {
    if (!_allowed() || candidates.isEmpty) return [];

    await _ensureSession();
    final safeLimit = limit.clamp(1, 100).toInt();
    final key = _cacheKey(context, candidates, experimentName);
    final cached = _cache[key];

    if (cached != null && !cached.expired(_config.recommendationCacheTtl)) {
      _touchCache(key, cached);
      return cached.items.take(safeLimit).toList();
    }

    await _writeEvent(
      BeastEventType.recommendationRequest,
      {
        'context': context,
        'candidate_count': candidates.length,
        'limit': safeLimit,
        'experiment': experimentName,
      },
    );

    if (_isColdStart()) {
      final cold = _coldStart(candidates, safeLimit);
      _cachePut(key, cold);
      return cold;
    }

    final contextVector = _contextVector(context);
    final ranked = <BeastRecommendation>[];

    for (final candidate in candidates) {
      if (preferences.isHidden(candidate.itemId)) continue;

      final signals = _predictCandidateSignals(
        candidate,
        contextVector: contextVector,
      );

      final banditSample = thompson.sample(candidate.itemId);
      final linScore = _linUcb?.score(candidate.itemId, contextVector) ?? 0;
      final exploreProbability = _explorationProbability(candidate.itemId);
      final explored = Random.secure().nextDouble() < exploreProbability;
      final exploration = explored ? banditSample * exploreProbability : 0.0;

      final score = _combineScores(
        candidate: candidate,
        signals: signals,
        linScore: linScore,
        banditSample: banditSample,
        exploration: exploration,
      );

      final strategy = explored
          ? BeastStrategy.exploration
          : signals.sessionIntent
              ? BeastStrategy.sessionBased
              : BeastStrategy.personalized;

      ranked.add(
        BeastRecommendation(
          itemId: candidate.itemId,
          score: score,
          confidence: _confidence(brain.impressions[candidate.itemId] ?? 0),
          strategy: strategy,
          source: 'edge',
          reason: _explain(candidate, signals),
          explanationSignals: _explanationSignals(candidate, signals),
          signals: {
            'relevance': signals.relevance,
            'preference': signals.preference,
            'category': signals.category,
            'creator': signals.creator,
            'item': signals.item,
            'ctr': signals.ctr,
            'skip_rate': signals.skipRate,
            'exposure': signals.exposure,
            'recency': signals.recency,
            'sequence': signals.sequence,
            'time': signals.time,
            'novelty': signals.novelty,
            'social': signals.social,
            'quality': signals.quality,
            'prediction': signals.prediction,
            'linucb': linScore,
            'bandit': banditSample,
            'exploration': exploration,
          },
          metadata: {
            ...candidate.metadata,
            'category': candidate.category,
            'creator_id': candidate.creatorId,
            'tags': candidate.tags,
            'explored': explored,
            'model_version': _modelVersion,
          },
        ),
      );
    }

    ranked.sort((a, b) => b.score.compareTo(a.score));

    var result = diversity
        ? _mmr(ranked, safeLimit)
        : ranked.take(safeLimit).toList();

    if (useBigBeast) {
      final remote = await _fetchBigBeast(context, safeLimit);
      if (remote.isNotEmpty) {
        result = _mergeAndRerank(result, remote, safeLimit);
      }
    }

    _cachePut(key, result);

    await _writeEvent(
      BeastEventType.recommendationServed,
      {
        'context': context,
        'count': result.length,
        'model_version': _modelVersion,
        'items': result.take(30).map((e) => e.toJson()).toList(),
      },
    );

    return result;
  }

  Stream<List<BeastRecommendation>> recommendProgressive(
    List<BeastCandidate> candidates, {
    required String context,
    int limit = 20,
  }) async* {
    if (!_allowed()) {
      yield const [];
      return;
    }

    final local = await recommend(
      candidates,
      context: context,
      limit: limit,
      useBigBeast: false,
      diversity: true,
    );
    yield local;

    final remote = await _fetchBigBeast(
      context,
      limit.clamp(1, 100).toInt(),
    );
    if (remote.isNotEmpty) {
      yield _mergeAndRerank(
        local,
        remote,
        limit.clamp(1, 100).toInt(),
      );
    }
  }

  // --------------------------------------------------------------------------
  // FEATURES
  // --------------------------------------------------------------------------

  _CandidateSignals _predictCandidateSignals(
    BeastCandidate candidate, {
    List<double>? contextVector,
  }) {
    final preference = brain.tagAffinity(candidate.tags);
    final category = brain.categoryScore(candidate.category);
    final creator = brain.creatorScore(candidate.creatorId);
    final item = brain.itemScore(candidate.itemId);
    final ctr = brain.ctr(candidate.itemId);
    final skipRate = brain.skipRate(candidate.itemId);
    final exposure = brain.exposurePenalty(candidate.itemId);
    final recency = brain.recency(candidate.itemId);
    final sequence = brain.sequenceScore(candidate.itemId);
    final time = _timeAwareScore(candidate);
    final novelty = _noveltyScore(candidate);
    final social = _socialScore(candidate);
    final quality = (candidate.features['quality'] ?? 0.5).clamp(0.0, 1.0).toDouble();
    final business = (candidate.features['business'] ?? 0.0).clamp(0.0, 1.0).toDouble();
    final session = _sessionIntentScore(candidate);
    final prediction = brain.predictTags(candidate.tags);

    final relevance = _squash(
      preference + category * 0.55 + creator * 0.60 + item * 0.20,
    );

    return _CandidateSignals(
      relevance: relevance,
      preference: preference,
      category: category,
      creator: creator,
      item: item,
      ctr: ctr,
      skipRate: skipRate,
      exposure: exposure,
      recency: recency,
      sequence: sequence,
      time: time,
      novelty: novelty,
      social: social,
      quality: quality,
      business: business,
      session: session,
      prediction: prediction,
      sessionIntent: session > 0.45,
    );
  }

  List<double> _contextVector(String context) {
    final vector = brain.sessionEmbedding(_config.embeddingDimension);
    final now = DateTime.now();
    if (vector.isNotEmpty) vector[0] = now.hour / 23.0;
    if (vector.length > 1) vector[1] = (now.weekday - 1) / 6.0;
    if (vector.length > 2) {
      vector[2] = min(
        1.0,
        _sessionAgeMs() / const Duration(hours: 2).inMilliseconds,
      );
    }
    if (vector.length > 3) vector[3] = _stableHash(context) / 0x7fffffff;
    return vector;
  }

  double _combineScores({
    required BeastCandidate candidate,
    required _CandidateSignals signals,
    required double linScore,
    required double banditSample,
    required double exploration,
  }) {
    var result = _ranker.score(
      relevance: signals.relevance,
      watchTime: _predictedWatchTime(candidate),
      quality: signals.quality,
      novelty: signals.novelty,
      diversity: preferences.diversityPreference,
      social: signals.social,
      business: signals.business,
    );

    result += signals.session * 0.65;
    result += signals.time * 0.30;
    result += signals.sequence * 0.50;
    result += signals.recency * 0.18;
    result += signals.ctr * 0.60;
    result += _squash(signals.prediction - 0.5) * 0.40;
    result += linScore * 0.25;
    result += _squash(banditSample - 0.5) * 0.30;
    result += exploration;

    result -= signals.exposure;
    result -= signals.skipRate * 0.80;
    result += preferences.itemAdjustment(candidate.itemId) * 0.25;

    if (candidate.category != null) {
      result += preferences.topicAdjustment(candidate.category!) * 0.20;
    }
    if (candidate.creatorId != null) {
      result += preferences.creatorAdjustment(candidate.creatorId!) * 0.20;
    }

    final twoTower = twoTowerScore(candidate);
    result += twoTower * 0.20;
    return result;
  }

  double _predictedWatchTime(BeastCandidate candidate) =>
      (candidate.features['watch_time_prediction'] ??
              candidate.features['expected_dwell'] ??
              0.5)
          .clamp(0.0, 1.0).toDouble();

  double _sessionIntentScore(BeastCandidate candidate) {
    if (brain.sessionInterests.isEmpty || candidate.tags.isEmpty) return 0;
    var score = 0.0;
    for (final tag in candidate.tags) {
      score += brain.sessionInterests[_norm(tag)] ?? 0;
    }
    return _squash(score / max(1, candidate.tags.length));
  }

  double _timeAwareScore(BeastCandidate candidate) {
    final hour = DateTime.now().hour;
    var score = 0.0;
    if (hour >= 6 && hour < 11) {
      score += candidate.features['morning_affinity'] ?? 0;
    } else if (hour >= 11 && hour < 15) {
      score += candidate.features['midday_affinity'] ?? 0;
    } else if (hour >= 15 && hour < 19) {
      score += candidate.features['afternoon_affinity'] ?? 0;
    } else {
      score += candidate.features['evening_affinity'] ?? 0;
    }
    if (DateTime.now().weekday >= DateTime.saturday) {
      score += candidate.features['weekend_affinity'] ?? 0;
    }
    return score.clamp(-1.0, 1.0).toDouble();
  }

  double _noveltyScore(BeastCandidate candidate) {
    final seen = brain.impressions[candidate.itemId] ?? 0;
    final base = candidate.features['novelty'] ??
        (seen == 0 ? 1.0 : 1.0 / (seen + 1));
    return (base * preferences.noveltyPreference).clamp(0.0, 1.0).toDouble();
  }

  double _socialScore(BeastCandidate candidate) {
    if (candidate.socialSignals.isEmpty) return 0;
    var score = 0.0;
    for (final s in candidate.socialSignals) {
      if (s == 'friend_liked') score += 0.5;
      if (s == 'following_creator') score += 0.3;
      if (s == 'community_trending') score += 0.2;
    }
    return score.clamp(0.0, 1.0).toDouble();
  }

  double twoTowerScore(BeastCandidate candidate) {
    final user = brain.sessionEmbedding(_config.embeddingDimension);
    final item = candidate.embedding ?? _hashVector(
      candidate.itemId,
      _config.embeddingDimension,
    );
    return _cosine(user, item);
  }

  // --------------------------------------------------------------------------
  // COLD START
  // --------------------------------------------------------------------------

  bool _isColdStart() => brain.recent.length < 5;

  int coldStartLevel() {
    final count = brain.recent.length;
    if (count == 0) return 0;
    if (count < 3) return 1;
    if (count < 5) return 2;
    return 3;
  }

  List<BeastRecommendation> _coldStart(
    List<BeastCandidate> candidates,
    int limit,
  ) {
    final level = coldStartLevel();
    final items = candidates.map((candidate) {
      final score = switch (level) {
        0 => (candidate.features['popular'] ?? 0.5) * 0.8 +
            (candidate.features['quality'] ?? 0.5) * 0.2,
        1 => (candidate.features['onboarding_match'] ?? 0.5) * 0.75 +
            (candidate.features['quality'] ?? 0.5) * 0.25,
        2 => (candidate.features['lookalike'] ?? 0.5) * 0.7 +
            (candidate.features['trending'] ?? 0.5) * 0.3,
        _ => (candidate.features['trending'] ?? 0.5) * 0.35 +
            (candidate.features['novelty'] ?? 0.5) * 0.35 +
            (candidate.features['quality'] ?? 0.5) * 0.30,
      };

      return BeastRecommendation(
        itemId: candidate.itemId,
        score: score,
        confidence: 0.25,
        strategy: level <= 1
            ? BeastStrategy.coldStart
            : BeastStrategy.exploration,
        source: 'edge-cold-start',
        reason: 'Cold-start level $level',
        explanationSignals: const ['cold_start'],
        signals: {'cold_start_level': level.toDouble(), 'score': score},
        metadata: candidate.metadata,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return _mmr(items, min(limit, items.length));
  }

  // --------------------------------------------------------------------------
  // DIVERSITY / MERGE
  // --------------------------------------------------------------------------

  List<BeastRecommendation> _mmr(
    List<BeastRecommendation> input,
    int topK,
  ) {
    if (input.length <= topK) return input.take(topK).toList();

    final remaining = List<BeastRecommendation>.from(input);
    final selected = <BeastRecommendation>[];

    while (selected.length < topK && remaining.isNotEmpty) {
      BeastRecommendation? best;
      var bestValue = double.negativeInfinity;

      for (final candidate in remaining) {
        var maxSimilarity = 0.0;
        for (final chosen in selected) {
          maxSimilarity = max(
            maxSimilarity,
            _recommendationSimilarity(candidate, chosen),
          );
        }

        final lambda =
            (0.55 + 0.35 * preferences.diversityPreference).clamp(0.35, 0.90).toDouble();
        final value =
            lambda * candidate.score - (1 - lambda) * maxSimilarity;

        if (value > bestValue) {
          bestValue = value;
          best = candidate;
        }
      }

      if (best == null) break;
      selected.add(best);
      remaining.remove(best);
    }

    return selected;
  }

  double _recommendationSimilarity(
    BeastRecommendation a,
    BeastRecommendation b,
  ) {
    final ca = a.metadata['category']?.toString();
    final cb = b.metadata['category']?.toString();
    if (ca != null && cb != null && ca == cb) return 0.75;

    final ta = a.metadata['tags'] is List
        ? Set<String>.from((a.metadata['tags'] as List).map((e) => e.toString()))
        : <String>{};
    final tb = b.metadata['tags'] is List
        ? Set<String>.from((b.metadata['tags'] as List).map((e) => e.toString()))
        : <String>{};

    if (ta.isEmpty || tb.isEmpty) return 0;
    final union = ta.union(tb).length;
    if (union == 0) return 0;
    return ta.intersection(tb).length / union;
  }

  List<BeastRecommendation> _mergeAndRerank(
    List<BeastRecommendation> local,
    List<BeastRecommendation> remote,
    int limit,
  ) {
    final map = <String, BeastRecommendation>{};

    for (final item in local) {
      map[item.itemId] = item;
    }

    for (final item in remote) {
      final old = map[item.itemId];
      if (old == null) {
        map[item.itemId] = item;
      } else {
        final blended = 0.55 * old.score + 0.45 * item.score;
        map[item.itemId] = BeastRecommendation(
          itemId: item.itemId,
          score: blended,
          confidence: max(old.confidence, item.confidence),
          strategy: item.strategy,
          source: 'hybrid',
          reason: item.reason ?? old.reason,
          explanationSignals: {
            ...old.explanationSignals,
            ...item.explanationSignals,
          }.toList(),
          signals: {...old.signals, 'server_score': item.score},
          metadata: {...old.metadata, ...item.metadata},
        );
      }
    }

    final merged = map.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return _mmr(merged, min(limit, merged.length));
  }

  double _explorationProbability(String itemId) {
    final exposure = brain.impressions[itemId] ?? 0;
    var value = preferences.explorationLevel;
    if (exposure == 0) value *= 1.75;
    if (exposure > 0 && exposure < 5) value *= 1.35;
    return value.clamp(0.01, 0.50).toDouble();
  }

  double _confidence(int impressions) =>
      (1 - 1 / sqrt(impressions + 2)).clamp(0.15, 0.95).toDouble();

  // --------------------------------------------------------------------------
  // EXPLAINABILITY / SEGMENTATION
  // --------------------------------------------------------------------------

  String _explain(
    BeastCandidate candidate,
    _CandidateSignals signals,
  ) {
    final parts = _explanationSignals(candidate, signals);
    return parts.isEmpty
        ? 'اختيار متوازن بناءً على السياق الحالي'
        : 'لأنك ${parts.join(' و')}';
  }

  List<String> _explanationSignals(
    BeastCandidate candidate,
    _CandidateSignals signals,
  ) {
    final result = <String>[];
    if (signals.preference > 0.40) result.add('تهتم بموضوعه');
    if (signals.session > 0.40) result.add('يناسب جلستك الحالية');
    if (signals.sequence > 0.25) result.add('يأتي بعد محتوى شاهدته');
    if (signals.creator > 0.50) result.add('من منشئ مناسب لاهتماماتك');
    if (signals.category > 0.50) result.add('من فئة تحبها');
    if (signals.novelty > 0.70) result.add('جديد بالنسبة لك');
    if (signals.social > 0.35) result.add('يحمل إشارة اجتماعية');
    if (signals.time > 0.25) result.add('مناسب لهذا الوقت');
    if (signals.relevance < 0.10) return const ['استكشاف شيء جديد'];
    return result.take(3).toList();
  }

  BeastUserSegment segmentUser() {
    final recent = brain.recent.length;
    final imp = brain.impressions.values.fold<int>(0, (a, b) => a + b);
    final opens = brain.opens.values.fold<int>(0, (a, b) => a + b);
    final ctr = imp == 0 ? 0.0 : opens / imp;
    final risk = churnRisk();

    if (recent >= 80 && ctr > 0.35) {
      return BeastUserSegment(
        id: 'power_user',
        confidence: 0.92,
        signals: {'ctr': ctr, 'recent_events': recent.toDouble()},
      );
    }
    if (risk > 0.70) {
      return BeastUserSegment(
        id: 'at_risk',
        confidence: risk,
        signals: {'churn_risk': risk},
      );
    }
    if (recent < 15) {
      return BeastUserSegment(
        id: 'new_or_casual',
        confidence: 0.85,
        signals: {'recent_events': recent.toDouble()},
      );
    }
    if (ctr < 0.10) {
      return BeastUserSegment(
        id: 'window_shopper',
        confidence: 0.80,
        signals: {'ctr': ctr},
      );
    }
    return BeastUserSegment(
      id: 'regular',
      confidence: 0.65,
      signals: {'ctr': ctr, 'momentum': brain.sessionMomentum()},
    );
  }

  double churnRisk() {
    if (_lastActivityAt == 0) return 1;
    final inactiveHours =
        max(0, DateTime.now().millisecondsSinceEpoch - _lastActivityAt) /
            Duration.millisecondsPerHour;
    final inactivityRisk = 1 - exp(-inactiveHours / 36.0);
    final momentumRisk = max(0.0, -brain.sessionMomentum());
    return (0.65 * inactivityRisk + 0.35 * momentumRisk).clamp(0.0, 1.0).toDouble();
  }

  double estimatedLtvScore() {
    final imp = brain.impressions.values.fold<int>(0, (a, b) => a + b);
    final opens = brain.opens.values.fold<int>(0, (a, b) => a + b);
    final ctr = imp == 0 ? 0 : opens / imp;
    final activity = min(1.0, brain.recent.length / 100.0);
    final retention = 1 - churnRisk();
    return (0.40 * ctr + 0.30 * activity + 0.30 * retention).clamp(0.0, 1.0).toDouble();
  }

  // --------------------------------------------------------------------------
  // A/B TESTS
  // --------------------------------------------------------------------------

  void registerExperiment({
    required String name,
    required List<String> variants,
    Map<String, double>? weights,
  }) {
    if (variants.isEmpty) return;
    _experiments[name] = _BeastExperiment(
      variants: List.unmodifiable(variants),
      weights: weights ?? {
        for (final variant in variants) variant: 1.0 / variants.length,
      },
    );

    if (_allowed()) {
      unawaited(
        _writeEvent(
          BeastEventType.experimentAssignment,
          {'experiment': name, 'variant': experimentVariant(name)},
        ),
      );
    }
  }

  String experimentVariant(String name) {
    final experiment = _experiments[name];
    if (experiment == null || experiment.variants.isEmpty) return 'control';

    final hash = _stableHash('$_userId::$name');
    final normalized = (hash % 100000) / 100000.0;
    var cumulative = 0.0;

    for (final variant in experiment.variants) {
      cumulative += experiment.weights[variant] ?? (1 / experiment.variants.length);
      if (normalized < cumulative) return variant;
    }

    return experiment.variants.last;
  }

  // --------------------------------------------------------------------------
  // PREFETCH
  // --------------------------------------------------------------------------

  Future<void> prefetch(
    List<BeastCandidate> candidates, {
    required String nextContext,
    int limit = 10,
  }) async {
    if (!_allowed()) return;
    final results = await recommend(
      candidates,
      context: nextContext,
      limit: limit,
      useBigBeast: true,
      diversity: true,
    );

    _cachePut(
      _cacheKey(nextContext, candidates, null),
      results,
    );

    await _writeEvent(
      BeastEventType.prefetch,
      {'context': nextContext, 'count': results.length},
    );
  }

  // --------------------------------------------------------------------------
  // MODEL / EXPERIENCE SYNC
  // --------------------------------------------------------------------------

  Future<void> syncExperiences() async {
    if (!_allowed() || _syncRunning || _db == null || _http == null) return;

    _syncRunning = true;
    try {
      final rows = await _db!.query(
        'experiences',
        where: 'synced = 0',
        orderBy: 'id ASC',
        limit: 200,
      );

      if (rows.isEmpty) return;

      final response = await _http!.post(
        Uri.parse('${_config.serverUrl}/v2/beast/experience/batch'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'user_id': _userId,
          'session_id': _sessionId,
          'model_version': _modelVersion,
          'experiences': rows,
          'brain_summary': brain.snapshot(),
          'preferences': preferences.toJson(),
          'segment': segmentUser().toJson(),
          // Optional client-side FL payload. Backend must secure-aggregate it.
          'local_update': createFederatedUpdate(),
        }),
      ).timeout(_config.requestTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final ids = rows.map((e) => e['id']).toList();
        if (ids.isNotEmpty) {
          final placeholders = List.filled(ids.length, '?').join(',');
          await _db!.rawUpdate(
            'UPDATE experiences SET synced = 1 WHERE id IN ($placeholders)',
            ids,
          );
        }

        final decoded = _decodeMap(response.body);
        if (decoded['model_update_available'] == true) {
          await syncModel();
        }
        await _trimSyncedExperiences();
      }
    } catch (e) {
      debugPrint('Beast experience sync failed: $e');
    } finally {
      _syncRunning = false;
    }
  }

  Future<void> syncModel() async {
    if (!_allowed() || _modelSyncRunning || _http == null) return;

    _modelSyncRunning = true;
    try {
      final response = await _http!.get(
        Uri.parse('${_config.serverUrl}/v2/beast/model'),
        headers: {'Accept': 'application/json'},
      ).timeout(_config.requestTimeout);

      if (response.statusCode != 200) return;
      final decoded = _decodeMap(response.body);
      final update = BeastModelUpdate.fromJson(decoded);

      _modelVersion = update.modelVersion;
      _learningRate = update.learningRate.clamp(0.0001, 0.5).toDouble();
      _explorationRate = update.explorationRate.clamp(0.01, 0.50).toDouble();

      if (update.banditState.isNotEmpty) {
        thompson.importState(update.banditState);
      }

      if (update.policy['linucb'] is Map && _linUcb != null) {
        _linUcb!.importState(
          Map<String, dynamic>.from(update.policy['linucb']),
        );
      }

      await _saveMeta('model_version', _modelVersion);
      await _saveMeta('learning_rate', '$_learningRate');
      await _saveMeta('exploration_rate', '$_explorationRate');
      await _saveMeta('bandit', jsonEncode(thompson.exportState()));
      if (_linUcb != null) {
        await _saveMeta('linucb', jsonEncode(_linUcb!.exportState()));
      }

      _cache.clear();

      await _writeEvent(
        BeastEventType.modelSync,
        {'model_version': _modelVersion},
      );
    } catch (e) {
      debugPrint('Beast model sync failed: $e');
    } finally {
      _modelSyncRunning = false;
    }
  }

  // --------------------------------------------------------------------------
  // EVENT QUEUE
  // --------------------------------------------------------------------------

  Future<void> flush() async {
    if (!_allowed() || _flushRunning || _db == null || _http == null) return;

    _flushRunning = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rows = await _db!.query(
        'events',
        where: 'next_retry_at <= ?',
        whereArgs: [now],
        orderBy: 'priority DESC, id ASC',
        limit: _config.batchSize,
      );

      if (rows.isEmpty) return;

      final events = <Map<String, dynamic>>[];
      final ids = <int>[];

      for (final row in rows) {
        try {
          final decoded = jsonDecode(row['payload'] as String);
          if (decoded is Map) {
            events.add(Map<String, dynamic>.from(decoded));
            ids.add(row['id'] as int);
          }
        } catch (_) {
          await _db!.delete(
            'events',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }

      if (events.isEmpty) return;

      final payload = jsonEncode({
        'user_id': _userId,
        'session_id': _sessionId,
        'model_version': _modelVersion,
        'events': events,
      });

      final request = http.Request(
        'POST',
        Uri.parse('${_config.serverUrl}/v2/beast/events/batch'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.headers['Accept'] = 'application/json';
      request.headers['Accept-Encoding'] = 'gzip';
      request.body = payload;

      if (_config.enableGzip && payload.length > 1024) {
        request.bodyBytes = GZipCodec().encode(utf8.encode(payload));
        request.headers['Content-Encoding'] = 'gzip';
      }

      final streamed = await _http!.send(request).timeout(_config.requestTimeout);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final placeholders = List.filled(ids.length, '?').join(',');
        await _db!.rawDelete(
          'DELETE FROM events WHERE id IN ($placeholders)',
          ids,
        );
      } else {
        await _scheduleRetry(rows);
      }
    } catch (e) {
      debugPrint('Beast flush failed: $e');
      final now = DateTime.now().millisecondsSinceEpoch;
      final rows = await _db!.query(
        'events',
        where: 'next_retry_at <= ?',
        whereArgs: [now],
        orderBy: 'priority DESC, id ASC',
        limit: _config.batchSize,
      );
      await _scheduleRetry(rows);
    } finally {
      _flushRunning = false;
    }
  }

  Future<void> _scheduleRetry(List<Map<String, Object?>> rows) async {
    final db = _db;
    if (db == null) return;

    final batch = db.batch();
    for (final row in rows) {
      final retry = ((row['retry_count'] as int?) ?? 0) + 1;
      final priority = (row['priority'] as int?) ?? 1;

      if (retry > 8 && priority <= 0) {
        batch.delete(
          'events',
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        continue;
      }

      final delay = min(
        900,
        pow(2, min(retry, 8)).toInt() + Random.secure().nextInt(8),
      );

      batch.update(
        'events',
        {
          'retry_count': retry,
          'next_retry_at': DateTime.now()
              .add(Duration(seconds: delay))
              .millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  // --------------------------------------------------------------------------
  // PERFORMANCE / NETWORK / CRASH
  // --------------------------------------------------------------------------

  void _startPerformanceMonitor() {
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _onFrame(Duration timestamp) {
    if (_ready && _allowed()) {
      final now = DateTime.now();
      if (_lastFrameAt != null) {
        final frameMs = now.difference(_lastFrameAt!).inMicroseconds / 1000.0;
        if (frameMs > 0) {
          _frameTimeEmaMs = 0.90 * _frameTimeEmaMs + 0.10 * frameMs;
        }
        if (frameMs > 32) _jankFrames++;
      }
      _lastFrameAt = now;
      _frameCount++;

      if (_frameCount % 120 == 0) {
        final fps = _frameTimeEmaMs <= 0 ? 0 : 1000 / _frameTimeEmaMs;
        unawaited(
          _writeEvent(
            BeastEventType.performance,
            {
              'fps': fps.round(),
              'frame_time_ms': _frameTimeEmaMs,
              'frames': _frameCount,
              'jank_frames': _jankFrames,
              'screen': _screen,
            },
            priority: 0,
          ),
        );
      }
    }
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  Future<void> _initNetwork() async {
    try {
      _network = await Connectivity().checkConnectivity();
      _networkSub = Connectivity().onConnectivityChanged.listen((value) async {
        _network = value;
        if (!_allowed()) return;

        await _writeEvent(
          BeastEventType.networkChange,
          {'type': value.name},
          priority: 0,
        );

        if (value != ConnectivityResult.none) {
          await syncExperiences();
          await flush();
        }
      });
    } catch (e) {
      debugPrint('Network monitor failed: $e');
    }
  }

  void _installCrashTracking() {
    FlutterError.onError = (details) {
      unawaited(
        _writeEvent(
          BeastEventType.error,
          {
            'source': 'flutter',
            'exception': details.exceptionAsString(),
            'stack': details.stack?.toString(),
            'context': details.context?.toString(),
          },
          priority: 3,
        ),
      );
      FlutterError.presentError(details);
    };

    ui.PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        _writeEvent(
          BeastEventType.error,
          {
            'source': 'platform',
            'error': error.toString(),
            'stack': stack.toString(),
          },
          priority: 3,
        ),
      );
      return true;
    };
  }

  void _attachTouchTracking() {
    GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
      if (event is PointerDownEvent) {
        recordPointerDown(event);
      }
    });
  }

  void recordPointerDown(PointerDownEvent event) {
    if (!_allowed() || !_config.autoTouchSummary) return;
    _touchCount++;
    if (_lastTouch != null) {
      _touchTravel += (event.position - _lastTouch!).distance;
    }
    _lastTouch = event.position;

    if (_config.privacy == BeastPrivacy.extensive &&
        _config.allowTouchCoordinates) {
      unawaited(
        _writeEvent(
          BeastEventType.touchSummary,
          {
            'x': event.position.dx,
            'y': event.position.dy,
            'single_touch': true,
          },
          priority: 0,
        ),
      );
    }
  }

  Future<void> flushTouchSummary() async {
    if (_touchCount <= 0 || !_allowed()) return;
    await _writeEvent(
      BeastEventType.touchSummary,
      {
        'count': _touchCount,
        'travel_px': _touchTravel,
      },
      priority: 0,
    );
    _touchCount = 0;
    _touchTravel = 0;
    _lastTouch = null;
  }

  // --------------------------------------------------------------------------
  // LOCAL DATABASE
  // --------------------------------------------------------------------------

  Future<void> _openDatabase() async {
    final root = await getDatabasesPath();

    _db = await openDatabase(
      p.join(root, 'beast_small_ultimate.db'),
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA journal_mode=WAL');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute(
              'ALTER TABLE experiences ADD COLUMN error REAL NOT NULL DEFAULT 0',
            );
          } catch (_) {}
        }
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL UNIQUE,
        event_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_events_ready '
      'ON events(next_retry_at, priority DESC, id)',
    );

    await db.execute('''
      CREATE TABLE experiences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        experience_id TEXT NOT NULL UNIQUE,
        item_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        reward REAL NOT NULL DEFAULT 0,
        prediction REAL NOT NULL DEFAULT 0,
        error REAL NOT NULL DEFAULT 0,
        position INTEGER NOT NULL DEFAULT 0,
        explored INTEGER NOT NULL DEFAULT 0,
        model_version TEXT NOT NULL,
        features TEXT NOT NULL,
        context TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_experiences_sync ON experiences(synced, id)',
    );

    await db.execute('''
      CREATE TABLE meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _loadPersistentState() async {
    final consent = await _readMeta('consent');
    if (consent == 'granted') _consent = BeastConsent.granted;
    if (consent == 'denied') _consent = BeastConsent.denied;

    _modelVersion = await _readMeta('model_version') ?? _modelVersion;
    _learningRate = double.tryParse(await _readMeta('learning_rate') ?? '') ?? _learningRate;
    _explorationRate = double.tryParse(await _readMeta('exploration_rate') ?? '') ?? _explorationRate;

    final banditRaw = await _readMeta('bandit');
    if (banditRaw != null) {
      try {
        final decoded = jsonDecode(banditRaw);
        if (decoded is Map) {
          thompson.importState(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }

    final linRaw = await _readMeta('linucb');
    if (linRaw != null && _linUcb != null) {
      try {
        final decoded = jsonDecode(linRaw);
        if (decoded is Map) {
          _linUcb!.importState(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }

    final brainRaw = await _readMeta('brain');
    if (brainRaw != null) {
      try {
        final decoded = jsonDecode(brainRaw);
        if (decoded is Map) {
          brain.importState(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }

    final forgettingRaw = await _readMeta('forgetting');
    if (forgettingRaw != null) {
      try {
        final decoded = jsonDecode(forgettingRaw);
        if (decoded is Map) {
          forgetting.restore(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }

    await _loadPreferences();
  }

  Future<void> _saveMeta(String key, String value) async {
    await _db?.insert(
      'meta',
      {'key': _scopedMetaKey(key), 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> _readMeta(String key) async {
    final rows = await _db?.query(
          'meta',
          where: 'key = ?',
          whereArgs: [_scopedMetaKey(key)],
          limit: 1,
        ) ??
        [];
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  String _scopedMetaKey(String key) =>
      'user:${_userId.trim().isEmpty ? 'anonymous' : _userId.trim()}:$key';

  Future<void> _persistBrain() async {
    await _saveMeta(
      'brain',
      jsonEncode(brain.exportState()),
    );
  }

  Future<void> _persistForgetting() async {
    await _saveMeta(
      'forgetting',
      jsonEncode(forgetting.toJson()),
    );
  }

  Future<void> _persistLearningState() async {
    await _persistBrain();
    await _persistForgetting();
    await _saveMeta(
      'bandit',
      jsonEncode(thompson.exportState()),
    );
    if (_linUcb != null) {
      await _saveMeta(
        'linucb',
        jsonEncode(_linUcb!.exportState()),
      );
    }
    await _persistPreferences();
  }

  Future<void> _persistPreferences() async {
    await _saveMeta(
      'preferences',
      jsonEncode(preferences.toJson()),
    );
  }

  Future<void> _loadPreferences() async {
    final raw = await _readMeta('preferences');
    if (raw == null) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      if (decoded['topic_boost'] is Map) {
        preferences.topicBoost.addAll(_toDoubleMap(decoded['topic_boost']));
      }
      if (decoded['topic_block'] is Map) {
        preferences.topicBlock.addAll(_toDoubleMap(decoded['topic_block']));
      }
      if (decoded['creator_boost'] is Map) {
        preferences.creatorBoost.addAll(_toDoubleMap(decoded['creator_boost']));
      }
      if (decoded['creator_block'] is Map) {
        preferences.creatorBlock.addAll(_toDoubleMap(decoded['creator_block']));
      }
      if (decoded['item_adjustments'] is Map) {
        preferences.itemAdjustments.addAll(_toDoubleMap(decoded['item_adjustments']));
      }
      if (decoded['hidden_items'] is List) {
        preferences.hiddenItems.addAll(
          (decoded['hidden_items'] as List).map((e) => e.toString()),
        );
      }

      preferences.explorationLevel =
          (decoded['exploration_level'] as num?)?.toDouble().clamp(0, 1).toDouble() ??
              preferences.explorationLevel;
      preferences.noveltyPreference =
          (decoded['novelty_preference'] as num?)?.toDouble().clamp(0, 1).toDouble() ??
              preferences.noveltyPreference;
      preferences.diversityPreference =
          (decoded['diversity_preference'] as num?)?.toDouble().clamp(0, 1).toDouble() ??
              preferences.diversityPreference;
    } catch (_) {}
  }

  Future<void> _recordExperience({
    required String itemId,
    required String eventType,
    required double reward,
    required double prediction,
    required int position,
    required bool explored,
    required Map<String, double> features,
    required Map<String, dynamic> context,
  }) async {
    final db = _db;
    if (db == null || !_allowed()) return;

    final clippedReward = reward.clamp(-1.0, 1.0).toDouble();
    final error = clippedReward - prediction;

    await db.insert(
      'experiences',
      {
        'experience_id': _id(),
        'item_id': itemId,
        'event_type': eventType,
        'reward': clippedReward,
        'prediction': prediction,
        'error': error,
        'position': position,
        'explored': explored ? 1 : 0,
        'model_version': _modelVersion,
        'features': jsonEncode(features),
        'context': jsonEncode(context),
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await _trimExperiences();
  }

  Future<void> _writeEvent(
    BeastEventType type,
    Map<String, dynamic> data, {
    int priority = 1,
  }) async {
    if (!_allowed()) return;
    final db = _db;
    if (db == null) return;

    final now = DateTime.now();
    final event = {
      'event_id': _id(),
      'event_type': type.name,
      'user_id': _userId,
      'session_id': _sessionId,
      'screen': _screen,
      'model_version': _modelVersion,
      'timestamp': now.toUtc().toIso8601String(),
      'network': _network.name,
      'data': _sanitize(data),
    };

    await db.insert(
      'events',
      {
        'event_id': event['event_id'],
        'event_type': type.name,
        'payload': jsonEncode(event),
        'created_at': now.millisecondsSinceEpoch,
        'retry_count': 0,
        'next_retry_at': 0,
        'priority': priority,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    _eventStream.add(event);
    await _trimEvents();
  }

  // --------------------------------------------------------------------------
  // LOCAL DP / FEDERATED UPDATE CONTRACT
  // --------------------------------------------------------------------------

  double addLaplaceNoise(
    double value, {
    required double sensitivity,
    double epsilon = 1.0,
  }) {
    final safeEpsilon = max(1e-9, epsilon);
    final scale = sensitivity / safeEpsilon;
    final u = Random.secure().nextDouble() - 0.5;
    final sign = u < 0 ? -1.0 : 1.0;
    final noise = -scale * sign * log(1 - 2 * u.abs());
    return value + noise;
  }

  Map<String, dynamic> createFederatedUpdate({double epsilon = 1.0}) {
    final weights = brain.ftrlWeights();
    return {
      'model_version': _modelVersion,
      'local_weights': {
        for (final e in weights.entries)
          e.key: addLaplaceNoise(
            e.value,
            sensitivity: 1.0,
            epsilon: epsilon,
          ),
      },
      'segment': segmentUser().toJson(),
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  // --------------------------------------------------------------------------
  // LOCAL DATA EXPORT / DELETE
  // --------------------------------------------------------------------------

  Future<Map<String, dynamic>> exportLocalData() async => {
        'user_id': _userId,
        'session_id': _sessionId,
        'model_version': _modelVersion,
        'preferences': preferences.toJson(),
        'brain': brain.snapshot(),
        'pending_events': await pendingEvents(),
        'pending_experiences': await pendingExperiences(),
      };

  Future<int> pendingEvents() async {
    final result = await _db?.rawQuery(
          'SELECT COUNT(*) AS count FROM events',
        ) ??
        [];
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> pendingExperiences() async {
    final result = await _db?.rawQuery(
          'SELECT COUNT(*) AS count FROM experiences WHERE synced = 0',
        ) ??
        [];
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> deleteAllLocalData() async {
    brain.clear();
    preferences.clear();
    _cache.clear();
    await _db?.delete('events');
    await _db?.delete('experiences');
    await _db?.delete('meta');
    _consent = BeastConsent.notDetermined;
  }

  Future<void> _eraseBehavior() async {
    brain.clear();
    preferences.clear();
    _cache.clear();
    await _db?.delete('events');
    await _db?.delete('experiences', where: 'synced = 0');
    await _saveMeta('preferences', jsonEncode(preferences.toJson()));
  }

  // --------------------------------------------------------------------------
  // NOTIFICATIONS
  // --------------------------------------------------------------------------

  Future<void> _initNotifications() async {
    _notifications = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
    );
    await _notifications!.initialize(settings: settings);
  }

  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_config.enableNotifications || _notifications == null) return;

    const androidDetails = AndroidNotificationDetails(
      'beast_channel',
      'Beast Notifications',
      channelDescription: 'Beast local recommendation notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notifications!.show(
      id,
      title,
      body,
      notificationDetails: details,
      payload: payload,
    );
  }

  // --------------------------------------------------------------------------
  // CLEANUP
  // --------------------------------------------------------------------------

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    if (analyticsEnabled) {
      await _writeEvent(
        BeastEventType.sessionEnd,
        {'session_age_ms': _sessionAgeMs()},
        priority: 3,
      );
      await flushTouchSummary();
      await syncExperiences();
      await flush();
    }

    _flushTimer?.cancel();
    _modelTimer?.cancel();
    await _networkSub?.cancel();
    await _db?.close();
    _http?.close();
    await _eventStream.close();

    _db = null;
    _http = null;
    _ready = false;
  }

  // --------------------------------------------------------------------------
  // INTERNAL HELPERS
  // --------------------------------------------------------------------------

  bool _allowed() =>
      _ready &&
      !_disposed &&
      _consent == BeastConsent.granted;

  Future<void> _ensureSession() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_sessionStartedAt == 0 ||
        now - _lastActivityAt > _config.sessionTimeout.inMilliseconds) {
      _sessionId = _id();
      _sessionStartedAt = now;
      brain.sessionInterests.clear();
      brain.sessionDislikes.clear();
      await _writeEvent(
        BeastEventType.sessionStart,
        {'session_id': _sessionId},
        priority: 3,
      );
    }
    _lastActivityAt = now;
  }

  int _sessionAgeMs() =>
      _sessionStartedAt == 0
          ? 0
          : max(
              0,
              DateTime.now().millisecondsSinceEpoch - _sessionStartedAt,
            );

  Future<void> _trimEvents() async {
    final db = _db;
    if (db == null) return;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM events',
    );
    final count = Sqflite.firstIntValue(result) ?? 0;
    if (count <= _config.maxEvents) return;

    await db.delete(
      'events',
      where:
          'id IN (SELECT id FROM events ORDER BY priority ASC, id ASC LIMIT ?)',
      whereArgs: [count - _config.maxEvents],
    );
  }

  Future<void> _trimExperiences() async {
    final db = _db;
    if (db == null) return;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM experiences',
    );
    final count = Sqflite.firstIntValue(result) ?? 0;
    if (count <= _config.maxExperiences) return;

    await db.delete(
      'experiences',
      where:
          'id IN (SELECT id FROM experiences ORDER BY synced DESC, id ASC LIMIT ?)',
      whereArgs: [count - _config.maxExperiences],
    );
  }

  Future<void> _trimSyncedExperiences() async {
    final db = _db;
    if (db == null) return;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM experiences WHERE synced = 1',
    );
    final count = Sqflite.firstIntValue(result) ?? 0;
    if (count <= _config.retainedSyncedExperiences) return;

    await db.delete(
      'experiences',
      where:
          'id IN (SELECT id FROM experiences WHERE synced = 1 ORDER BY id ASC LIMIT ?)',
      whereArgs: [count - _config.retainedSyncedExperiences],
    );
  }

  List<double> _hashVector(String text, int dimension) {
    final random = Random(_stableHash(text));
    final vector = List<double>.generate(
      dimension,
      (_) => random.nextDouble() * 2 - 1,
    );
    return _normalize(vector);
  }

  List<double> _normalize(List<double> vector) {
    var norm = 0.0;
    for (final x in vector) norm += x * x;
    norm = sqrt(norm);
    if (norm <= 0) return vector;
    return vector.map((x) => x / norm).toList();
  }

  double _cosine(List<double> a, List<double> b) {
    final n = min(a.length, b.length);
    if (n == 0) return 0;
    var dot = 0.0;
    var aa = 0.0;
    var bb = 0.0;
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
      aa += a[i] * a[i];
      bb += b[i] * b[i];
    }
    if (aa <= 0 || bb <= 0) return 0;
    return dot / sqrt(aa * bb);
  }

  Map<String, double> _tagVector(List<String> tags) => {
        for (final tag in tags) 'tag:${_norm(tag)}': 1.0,
      };

  double _durationReward(int durationMs) {
    final seconds = durationMs / 1000.0;
    return min(1.0, log(1 + seconds) / log(121));
  }

  double _squash(double x) => tanh(x / 5);

  String _cacheKey(
    String context,
    List<BeastCandidate> candidates,
    String? experiment,
  ) =>
      '$context::${candidates.take(80).map((e) => e.itemId).join('|')}::$experiment::$_modelVersion';

  void _cachePut(
    String key,
    List<BeastRecommendation> items,
  ) {
    _cache.remove(key);
    _cache[key] = _RecommendationCacheEntry(
      items,
      DateTime.now(),
    );
    while (_cache.length > _config.maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _touchCache(
    String key,
    _RecommendationCacheEntry entry,
  ) {
    _cache.remove(key);
    _cache[key] = entry;
  }

  Future<List<BeastRecommendation>> _fetchBigBeast(
    String context,
    int limit,
  ) async {
    if (_http == null || _config.serverUrl.trim().isEmpty) return [];

    try {
      final response = await _http!.post(
        Uri.parse('${_config.serverUrl}/v2/beast/recommend'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'user_id': _userId,
          'session_id': _sessionId,
          'model_version': _modelVersion,
          'context': {
            'screen': _screen,
            'hour': DateTime.now().hour,
            'weekday': DateTime.now().weekday,
            'session_age_sec': _sessionAgeMs() ~/ 1000,
            'network': _network.name,
            'brain': brain.snapshot(),
            'preferences': preferences.toJson(),
            'segment': segmentUser().toJson(),
          },
          'limit': limit,
        }),
      ).timeout(_config.requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) return [];

      final decoded = _decodeMap(response.body);
      final rawItems = decoded['items'];
      if (rawItems is! List) return [];

      return rawItems.whereType<Map>().map((item) {
        return BeastRecommendation(
          itemId: item['item_id']?.toString() ?? '',
          score: (item['score'] as num?)?.toDouble() ?? 0,
          confidence: (item['confidence'] as num?)?.toDouble() ?? 0.5,
          strategy: _parseStrategy(item['strategy']?.toString()),
          source: 'server',
          reason: item['reason']?.toString(),
          explanationSignals: item['explanation_signals'] is List
              ? List<String>.from(item['explanation_signals'])
              : const [],
          signals: item['signals'] is Map
              ? (item['signals'] as Map).map(
                  (key, value) => MapEntry(
                    key.toString(),
                    value is num ? value.toDouble() : 0.0,
                  ),
                )
              : const {},
          metadata: item['metadata'] is Map
              ? Map<String, dynamic>.from(item['metadata'])
              : const {},
        );
      }).where((e) => e.itemId.isNotEmpty).toList();
    } catch (e) {
      debugPrint('Big Beast recommendation request failed: $e');
      return [];
    }
  }

  BeastStrategy _parseStrategy(String? value) =>
      BeastStrategy.values.firstWhere(
        (e) => e.name == value,
        orElse: () => BeastStrategy.personalized,
      );

  Map<String, dynamic> _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return {};
  }

  Map<String, double> _toDoubleMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (key, raw) => MapEntry(
        key.toString(),
        raw is num ? raw.toDouble() : 0.0,
      ),
    );
  }

  Map<String, dynamic> _sanitize(
    Map<String, dynamic> data,
  ) {
    final output = <String, dynamic>{};
    const blocked = {
      'password',
      'passwd',
      'token',
      'authorization',
      'access_token',
      'refresh_token',
      'secret',
      'private_key',
      'api_key',
      'card_number',
      'cvv',
      'message_body',
      'raw_text',
      'raw_query',
    };

    for (final entry in data.entries) {
      final key = entry.key.toLowerCase();
      if (blocked.contains(key)) continue;

      final value = entry.value;
      if (value == null ||
          value is num ||
          value is bool ||
          value is String) {
        output[entry.key] =
            _config.privacy == BeastPrivacy.minimal && value is String
                ? value.length
                : value;
      } else if (value is List) {
        output[entry.key] = value.take(50).toList();
      } else if (value is Map) {
        output[entry.key] = _sanitize(
          Map<String, dynamic>.from(value),
        );
      }
    }

    return output;
  }

  String _norm(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  int _stableHash(String text) {
    var hash = 2166136261;
    for (final code in text.codeUnits) {
      hash ^= code;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
}

// ============================================================================
// NAVIGATOR OBSERVER
// ============================================================================

class BeastNavigatorObserver extends NavigatorObserver {
  final BeastUltimate beast;
  BeastNavigatorObserver(this.beast);

  String _routeName(Route<dynamic>? route) {
    final name = route?.settings.name;
    return name == null || name.isEmpty
        ? route?.runtimeType.toString() ?? 'unknown'
        : name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    unawaited(beast.screen(_routeName(route)));
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    unawaited(beast.screen(_routeName(previousRoute)));
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    unawaited(beast.screen(_routeName(newRoute)));
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

// ============================================================================
// LIFECYCLE OBSERVER
// ============================================================================

class _LifecycleObserver with WidgetsBindingObserver {
  final BeastUltimate beast;
  _LifecycleObserver(this.beast);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(beast.onForeground());
        break;
      case AppLifecycleState.paused:
        unawaited(beast.onBackground());
        break;
      case AppLifecycleState.inactive:
        unawaited(beast.onInactive());
        break;
      case AppLifecycleState.hidden:
        unawaited(beast.onHidden());
        break;
      case AppLifecycleState.detached:
        unawaited(beast.dispose());
        break;
    }
  }
}

// ============================================================================
// INTERNAL DATA
// ============================================================================

class _RecommendationCacheEntry {
  final List<BeastRecommendation> items;
  final DateTime createdAt;

  const _RecommendationCacheEntry(
    this.items,
    this.createdAt,
  );

  bool expired(Duration ttl) =>
      DateTime.now().difference(createdAt) > ttl;
}

class _BeastExperiment {
  final List<String> variants;
  final Map<String, double> weights;

  const _BeastExperiment({
    required this.variants,
    required this.weights,
  });
}


// ============================================================================
// BEAST SMALL ULTIMATE
// ============================================================================
// Single-file on-device recommendation/behavior engine for Flutter.
//
// Included local capabilities:
// - consent + privacy-safe telemetry
// - durable offline event queue + retry/backoff + gzip
// - session/lifecycle/route/network/performance tracking
// - short/medium/long-term behavioral memory
// - interests, dislikes, creator/category/item affinity
// - recency, exposure, repetition and fatigue signals
// - session intent + session momentum
// - Markov-style sequence mining
// - FTRL-style online tag learning
// - Thompson Sampling
// - diagonal LinUCB contextual bandit
// - two-tower-style local vector scoring when embeddings are supplied
// - multi-objective ranking
// - MMR diversity
// - cold-start levels
// - explainable recommendations
// - user controls: hide / less-like / more-like / topic preferences
// - time-aware and social/context signals
// - local segmentation + churn/LTV heuristics
// - A/B assignment
// - progressive recommendations + predictive prefetch hook
// - experience buffer with prediction/reward/error
// - model versioning + Big Beast sync contracts
// - privacy-aware local differential-privacy helper
// - federated-update payload helper
//
// Deliberate boundary:
// The phone cannot magically infer arbitrary app-domain semantics. The app
// still calls semantic methods for content/card/video/search actions. Global
// vector databases, Transformer/BERT training, two-tower training, multi-modal
// encoders, RL training, global stream processing, cross-user segmentation,
// global fairness audit, and secure federated aggregation belong on the Big
// Beast/backend. This file exposes the client-side contracts needed by them.
// ============================================================================

// ============================================================================
// ENUMS
// ============================================================================

enum BeastConsentV2 { notDetermined, granted, denied }

/// مستوى الخصوصية (يحدد كثافة البيانات المجمعة)
enum BeastPrivacyV2 { minimal, standard, extensive }

/// حالة Circuit Breaker
enum CircuitState { closed, open, halfOpen }

/// مصدر التوصية
enum RecSource { edge, server, cache, fallback, coldStart }

/// استراتيجية التوصية
enum RecStrategy {
  personalized,
  sessionBased,
  collaborative,
  contentBased,
  trending,
  popular,
  exploration,
  coldStart,
}

// ═══════════════════════════════════════════════════════════
// ⚙️ القسم 2: الإعدادات
// ═══════════════════════════════════════════════════════════

class BeastConfigV2 {
  // إعدادات الخادم
  final String serverUrl;
  final Duration requestTimeout;
  final Duration flushInterval;
  final Duration sessionTimeout;
  final Duration modelSyncInterval;

  // حدود التخزين
  final int batchSize;
  final int maxEvents;
  final int maxExperiences;
  final int maxBreadcrumbs;

  // إعدادات الخوارزميات
  final double explorationRate;
  final double diversityLambda;
  final int coldStartThreshold;

  // الخصوصية والأمان
  final BeastPrivacyV2 privacy;
  final bool enableCrashTracking;
  final bool enableGestureTracking;
  final bool enableGzip;
  final bool enableRedaction;

  // التتبع التلقائي
  final bool autoRoutes;
  final bool autoLifecycle;
  final bool autoPerformance;
  final bool autoNetwork;

  const BeastConfigV2({
    this.serverUrl = 'https://your-app.up.railway.app',
    this.requestTimeout = const Duration(seconds: 6),
    this.flushInterval = const Duration(seconds: 12),
    this.sessionTimeout = const Duration(minutes: 30),
    this.modelSyncInterval = const Duration(minutes: 30),
    this.batchSize = 100,
    this.maxEvents = 10000,
    this.maxExperiences = 5000,
    this.maxBreadcrumbs = 50,
    this.explorationRate = 0.15,
    this.diversityLambda = 0.7,
    this.coldStartThreshold = 10,
    this.privacy = BeastPrivacyV2.standard,
    this.enableCrashTracking = true,
    this.enableGestureTracking = false,
    this.enableGzip = true,
    this.enableRedaction = true,
    this.autoRoutes = true,
    this.autoLifecycle = true,
    this.autoPerformance = true,
    this.autoNetwork = true,
  });
}

// ═══════════════════════════════════════════════════════════
// 📦 القسم 3: نماذج البيانات
// ═══════════════════════════════════════════════════════════

/// مرشح للتوصية
class BeastCandidateV2 {
  final String itemId;
  final List<String> tags;
  final String? category;
  final Map<String, double> features;
  final Map<String, dynamic> metadata;

  const BeastCandidateV2({
    required this.itemId,
    this.tags = const [],
    this.category,
    this.features = const {},
    this.metadata = const {},
  });
}

/// توصية كاملة مع تفسير
class BeastRecommendationV2 {
  final String itemId;
  final double score;
  final double confidence;
  final RecStrategy strategy;
  final RecSource source;
  final Map<String, double> signals;
  final Map<String, dynamic> metadata;
  final String reason; // ✅ Explainable AI
  final String? abTestVariant;

  const BeastRecommendationV2({
    required this.itemId,
    required this.score,
    required this.confidence,
    required this.strategy,
    required this.source,
    this.signals = const {},
    this.metadata = const {},
    required this.reason,
    this.abTestVariant,
  });

  Map<String, dynamic> toJson() => {
        'item_id': itemId,
        'score': score,
        'confidence': confidence,
        'strategy': strategy.name,
        'source': source.name,
        'signals': signals,
        'metadata': metadata,
        'reason': reason,
      };
}

/// تفاعل المستخدم (Feedback)
class BeastInteraction {
  final String itemId;
  final String eventType;
  final int timestamp;
  final List<String> tags;
  final double reward;
  final Map<String, dynamic> context;

  BeastInteraction({
    required this.itemId,
    required this.eventType,
    required this.timestamp,
    this.tags = const [],
    this.reward = 0.0,
    this.context = const {},
  });
}

/// سجل الفتات (للتحليل بعد الانهيار)
class Breadcrumb {
  final String event;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  Breadcrumb({
    required this.event,
    this.data = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'event': event,
        'data': data,
        'ts': timestamp.millisecondsSinceEpoch,
      };
}

// ═══════════════════════════════════════════════════════════
// 🧠 القسم 4: BeastBrainV2 - الذاكرة المحلية الذكية
// ═══════════════════════════════════════════════════════════

class BeastBrainV2 {
  // الاهتمامات والكراهية
  final Map<String, double> interests = {};
  final Map<String, double> dislikes = {};
  final Map<String, double> itemAffinity = {};
  final Map<String, int> impressions = {};
  final Map<String, int> opens = {};
  final Map<String, int> lastSeenAt = {};
  final Map<String, int> clickCount = {};

  // السجل الأخير (Ring Buffer)
  final Queue<BeastInteraction> recentHistory = Queue();

  // FTRL-Proximal للتعلم الفوري
  final Map<String, double> _ftrlZ = {};
  final Map<String, double> _ftrlN = {};
  final double _alpha = 0.1;
  final double _beta = 1.0;
  final double _lambda1 = 0.1; // sparsity
  final double _lambda2 = 0.1; // regularization

  static const int maxHistorySize = 200;

  /// معالجة تفاعل جديد
  void ingest(BeastInteraction interaction) {
    recentHistory.addLast(interaction);
    while (recentHistory.length > maxHistorySize) {
      recentHistory.removeFirst();
    }

    final itemId = interaction.itemId;
    final reward = interaction.reward;

    if (itemId.isNotEmpty) {
      itemAffinity[itemId] = (itemAffinity[itemId] ?? 0) * 0.995 + reward;
      lastSeenAt[itemId] = interaction.timestamp;
    }

    if (interaction.eventType == 'impression') {
      impressions[itemId] = (impressions[itemId] ?? 0) + 1;
    }
    if (interaction.eventType == 'open' || interaction.eventType == 'click') {
      opens[itemId] = (opens[itemId] ?? 0) + 1;
      clickCount[itemId] = (clickCount[itemId] ?? 0) + 1;
    }

    // تحديث FTRL-Proximal (التعلم الفوري)
    final features = _extractFeatures(interaction);
    if (reward != 0) {
      _updateFTRL(features, reward > 0 ? 1.0 : 0.0);
    }

    // تحديث الاهتمامات والكراهية
    if (interaction.tags.isNotEmpty && reward != 0) {
      final perTag = reward / interaction.tags.length;
      for (final raw in interaction.tags) {
        final tag = _normalize(raw);
        if (tag.isEmpty) continue;
        if (perTag >= 0) {
          interests[tag] = (interests[tag] ?? 0) + perTag;
        } else {
          dislikes[tag] = (dislikes[tag] ?? 0) + perTag.abs();
        }
      }
    }
  }

  /// تحديث FTRL-Proximal الصحيح (مع Sparse Filtering)
  void _updateFTRL(Map<String, double> features, double label) {
    for (final entry in features.entries) {
      final feature = entry.key;
      final value = entry.value;
      if (value == 0) continue;

      final z = _ftrlZ[feature] ?? 0.0;
      final n = _ftrlN[feature] ?? 0.0;

      // حساب weight الحالي
      final currentWeight = _computeWeight(z, n);

      // تحديث n
      final newN = n + value * value;
      final sigma = (sqrt(newN) - sqrt(n)) / _alpha;

      // تحديث z
      _ftrlZ[feature] = z + value * (label - _sigmoid(currentWeight)) - sigma * currentWeight;
      _ftrlN[feature] = newN;
    }
  }

  double _computeWeight(double z, double n) {
    // ✅ Sparse FTRL: إذا كانت |z| صغيرة، weight = 0
    if (z.abs() <= _lambda1) return 0.0;
    final sign = z < 0 ? -1.0 : 1.0;
    return -(z - sign * _lambda1) / ((_beta + sqrt(n)) / _alpha + _lambda2);
  }

  double _sigmoid(double x) => 1 / (1 + exp(-x));

  /// التنبؤ بمدى اهتمام المستخدم بعنصر
  double predict(List<String> tags) {
    if (tags.isEmpty) return 0.0;
    double score = 0.0;
    int validFeatures = 0;

    for (final raw in tags) {
      final tag = _normalize(raw);
      final feature = 'tag:$tag';
      final z = _ftrlZ[feature];
      final n = _ftrlN[feature];
      if (z == null || n == null || n == 0) continue;

      final weight = _computeWeight(z, n);
      score += weight;
      validFeatures++;
    }

    if (validFeatures == 0) return 0.0;
    return _squash(score / sqrt(validFeatures));
  }

  /// ألفة الوسوم (Tag Affinity)
  double tagAffinity(List<String> tags) {
    if (tags.isEmpty) return 0;
    double score = 0;
    for (final raw in tags) {
      final t = _normalize(raw);
      score += (interests[t] ?? 0) - (dislikes[t] ?? 0);
    }
    return score / tags.length;
  }

  /// نسبة النقر إلى الظهور (CTR)
  double ctr(String itemId) {
    final imp = impressions[itemId] ?? 0;
    if (imp == 0) return 0;
    return (opens[itemId] ?? 0) / imp;
  }

  /// تلاشي المعلومات القديمة (Decay)
  void decay() {
    const decayFactor = 0.965;
    interests.updateAll((_, v) => v * decayFactor);
    dislikes.updateAll((_, v) => v * decayFactor);
    itemAffinity.updateAll((_, v) => v * 0.970);
    _prune(interests);
    _prune(dislikes);
    _prune(itemAffinity);
  }

  /// أهم المواضيع
  List<String> topTopics(int limit) {
    final list = interests.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(limit).map((e) => e.key).toList();
  }

  /// عدد التفاعلات الكلية
  int get totalInteractions => impressions.values.fold(0, (a, b) => a + b);

  /// لقطة للحالة الحالية (للمزامنة مع الخادم)
  Map<String, dynamic> snapshot() => {
        'total_interactions': totalInteractions,
        'top_topics': topTopics(20),
        'interest': _topMap(interests, 30),
        'dislike': _topMap(dislikes, 15),
        'recent_items': recentHistory.toList().reversed.take(30).map((e) => e.itemId).where((e) => e.isNotEmpty).toList(),
        'recent_events': recentHistory.toList().reversed.take(30).map((e) => e.eventType).toList(),
        'model_size': _ftrlZ.length,
      };

  /// مسح الذاكرة بالكامل
  void clear() {
    interests.clear();
    dislikes.clear();
    itemAffinity.clear();
    impressions.clear();
    opens.clear();
    lastSeenAt.clear();
    clickCount.clear();
    recentHistory.clear();
    _ftrlZ.clear();
    _ftrlN.clear();
  }

  Map<String, double> _extractFeatures(BeastInteraction i) {
    return {for (final tag in i.tags) 'tag:${_normalize(tag)}': 1.0};
  }

  Map<String, double> _topMap(Map<String, double> source, int limit) {
    final list = source.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(list.take(limit));
  }

  void _prune(Map<String, double> map) {
    final dead = map.entries.where((e) => e.value.abs() < 0.05).map((e) => e.key).toList();
    for (final k in dead) {
      map.remove(k);
    }
  }

  String _normalize(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  double _squash(double x) => tanh(x / 3);
}

// ═══════════════════════════════════════════════════════════
// 🎲 القسم 5: BeastBanditV2 - Thompson Sampling
// ═══════════════════════════════════════════════════════════

class BeastBanditV2 {
  final Map<String, _BetaArmV2> _arms = {};
  final Random _rng = Random.secure();

  double sample(String itemId) {
    final arm = _arms.putIfAbsent(itemId, () => _BetaArmV2(1, 1));
    final x = _gamma(arm.alpha);
    final y = _gamma(arm.beta);
    final sum = x + y;
    return sum <= 0 ? 0.5 : x / sum;
  }

  void update(String itemId, double reward) {
    final arm = _arms.putIfAbsent(itemId, () => _BetaArmV2(1, 1));
    final r = reward.clamp(-1.0, 1.0);
    if (r >= 0) {
      arm.alpha += r + 0.01;
    } else {
      arm.beta += r.abs() + 0.01;
    }
  }

  Map<String, dynamic> exportState() => {
        for (final e in _arms.entries) e.key: {'alpha': e.value.alpha, 'beta': e.value.beta}
      };

  void importState(Map<String, dynamic> data) {
    _arms.clear();
    for (final e in data.entries) {
      final v = e.value;
      if (v is Map) {
        _arms[e.key] = _BetaArmV2(
          (v['alpha'] as num?)?.toDouble() ?? 1,
          (v['beta'] as num?)?.toDouble() ?? 1,
        );
      }
    }
  }

  double _gamma(double shape) {
    if (shape < 1) {
      return _gamma(shape + 1) * pow(_rng.nextDouble(), 1 / shape);
    }
    final d = shape - 1 / 3;
    final c = 1 / sqrt(9 * d);
    while (true) {
      final x = _normal();
      final v0 = 1 + c * x;
      if (v0 <= 0) continue;
      final v = v0 * v0 * v0;
      final u = _rng.nextDouble();
      if (u < 1 - 0.0331 * pow(x, 4)) return d * v;
      if (log(u) < 0.5 * x * x + d * (1 - v + log(v))) return d * v;
    }
  }

  double _normal() {
    var u1 = _rng.nextDouble();
    final u2 = _rng.nextDouble();
    if (u1 <= 0) u1 = 1e-12;
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }
}

class _BetaArmV2 {
  double alpha;
  double beta;
  _BetaArmV2(this.alpha, this.beta);
}

// ═══════════════════════════════════════════════════════════
// 🧭 القسم 6: Session Intent Detection
// ═══════════════════════════════════════════════════════════

enum SessionIntent { browsing, searching, learning, entertainment, shopping, unknown }

class SessionIntentDetector {
  static SessionIntent detect(BeastBrainV2 brain) {
    final recent = brain.recentHistory.toList().reversed.take(15).toList();
    if (recent.isEmpty) return SessionIntent.unknown;

    final searches = recent.where((e) => e.eventType == 'search').length;
    final opens = recent.where((e) => e.eventType == 'open').length;
    final dwells = recent.where((e) => e.eventType == 'dwell').length;
    final purchases = recent.where((e) => e.eventType == 'purchase').length;

    if (purchases > 0) return SessionIntent.shopping;
    if (searches >= 3) return SessionIntent.searching;
    if (opens >= 5 && dwells >= 3) return SessionIntent.learning;
    if (opens >= 4) return SessionIntent.browsing;
    if (dwells >= 2) return SessionIntent.entertainment;

    return SessionIntent.unknown;
  }

  /// تعزيز بناءً على نية الجلسة
  static double intentBoost(SessionIntent intent, BeastCandidateV2 c) {
    final tags = c.tags.map((t) => t.toLowerCase()).toSet();
    switch (intent) {
      case SessionIntent.searching:
        return tags.contains('tutorial') || tags.contains('how_to') ? 0.3 : 0.0;
      case SessionIntent.learning:
        return tags.contains('educational') || tags.contains('course') ? 0.4 : 0.0;
      case SessionIntent.entertainment:
        return tags.contains('movie') || tags.contains('comedy') ? 0.3 : 0.0;
      case SessionIntent.shopping:
        return tags.contains('product') || tags.contains('deal') ? 0.4 : 0.0;
      default:
        return 0.0;
    }
  }
}

// ═══════════════════════════════════════════════════════════
// ⏰ القسم 7: Time-Aware Recommendations
// ═══════════════════════════════════════════════════════════

class TimeAwareness {
  static double timeBoost(BeastCandidateV2 c) {
    final hour = DateTime.now().hour;
    final tags = c.tags.map((t) => t.toLowerCase()).toSet();

    // صباحاً (6-11): أخبار، بودكاست، رياضة
    if (hour >= 6 && hour < 11) {
      if (tags.contains('news') || tags.contains('podcast') || tags.contains('fitness')) {
        return 0.25;
      }
    }
    // وقت الغداء (11-14): وصفات سريعة
    else if (hour >= 11 && hour < 14) {
      if (tags.contains('recipe') || tags.contains('food') || tags.contains('quick')) {
        return 0.3;
      }
    }
    // بعد الظهر (14-18): محتوى خفيف
    else if (hour >= 14 && hour < 18) {
      if (tags.contains('casual') || tags.contains('short')) return 0.2;
    }
    // مساءً (18-23): أفلام، مسلسلات
    else if (hour >= 18 && hour < 23) {
      if (tags.contains('movie') || tags.contains('series') || tags.contains('long_form')) {
        return 0.3;
      }
    }
    // ليلاً (23-6): محتوى هادئ
    else {
      if (tags.contains('relax') || tags.contains('sleep') || tags.contains('asmr')) {
        return 0.35;
      }
    }

    return 0.0;
  }
}

// ═══════════════════════════════════════════════════════════
// 🎁 القسم 8: Cold Start Handler
// ═══════════════════════════════════════════════════════════

class ColdStartHandler {
  final BeastConfigV2 config;

  ColdStartHandler(this.config);

  bool isColdStart(BeastBrainV2 brain) {
    return brain.totalInteractions < config.coldStartThreshold;
  }

  List<BeastRecommendationV2> generate(
    List<BeastCandidateV2> candidates,
    int limit,
  ) {
    final scored = candidates.map((c) {
      final popularity = c.features['popularity'] ?? 0.5;
      final novelty = c.features['novelty'] ?? 0.3;
      final diversity = Random.secure().nextDouble() * 0.3;
      final score = popularity * 0.5 + novelty * 0.3 + diversity * 0.2;
      return BeastRecommendationV2(
        itemId: c.itemId,
        score: score,
        confidence: 0.3,
        strategy: RecStrategy.coldStart,
        source: RecSource.coldStart,
        signals: {'popularity': popularity, 'novelty': novelty},
        metadata: {...c.metadata, 'category': c.category, 'tags': c.tags},
        reason: _generateReason(c, 'cold_start'),
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }

  String _generateReason(BeastCandidateV2 c, String strategy) {
    switch (strategy) {
      case 'cold_start':
        return 'محتوى رائج حالياً، جرّبه!';
      default:
        return 'مختار بعناية لك';
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 🎯 القسم 9: Explainable AI (Reasons)
// ═══════════════════════════════════════════════════════════

class ExplainableAI {
  static String generateReason(
    BeastCandidateV2 c,
    Map<String, double> signals,
    bool explored,
  ) {
    final affinity = signals['affinity'] ?? 0.0;
    final ctr = signals['ctr'] ?? 0.0;
    final mlPrediction = signals['ml_prediction'] ?? 0.0;
    final tags = c.tags.take(3).join('، ');

    if (explored) {
      return '✨ تجربة محتوى جديد لك';
    }
    if (affinity > 1.5 && tags.isNotEmpty) {
      return '🎯 بناءً على اهتمامك بـ: $tags';
    }
    if (mlPrediction > 0.7) {
      return '🧠 يتطابق مع تفضيلاتك';
    }
    if (ctr > 0.4) {
      return '👥 شائع بين المستخدمين المشابهين لك';
    }
    final popularity = c.features['popularity'] ?? 0.0;
    if (popularity > 0.8) {
      return '🔥 الأكثر رواجاً الآن';
    }
    final recency = c.features['recency'] ?? 0.0;
    if (recency > 0.8) {
      return '🆕 محتوى جديد';
    }
    if (c.category != null) {
      return 'من فئة ${c.category}';
    }
    return '✨ مختار بعناية لك';
  }
}

// ═══════════════════════════════════════════════════════════
// 👤 القسم 10: User Controls
// ═══════════════════════════════════════════════════════════

class UserControls {
  final Set<String> _hiddenItems = {};
  final Set<String> _hiddenCategories = {};
  final Set<String> _lessLikeThis = {};
  final Set<String> _moreLikeThis = {};

  void hideItem(String itemId) => _hiddenItems.add(itemId);
  void hideCategory(String category) => _hiddenCategories.add(category);
  void lessLikeThis(String itemId) => _lessLikeThis.add(itemId);
  void moreLikeThis(String itemId) => _moreLikeThis.add(itemId);

  bool isHidden(String itemId) => _hiddenItems.contains(itemId);
  bool isCategoryHidden(String? category) =>
      category != null && _hiddenCategories.contains(category);
  bool wantsLess(String itemId) => _lessLikeThis.contains(itemId);
  bool wantsMore(String itemId) => _moreLikeThis.contains(itemId);

  /// تصفية العناصر المرفوضة
  List<BeastCandidateV2> filter(List<BeastCandidateV2> candidates) {
    return candidates.where((c) {
      if (isHidden(c.itemId)) return false;
      if (isCategoryHidden(c.category)) return false;
      return true;
    }).toList();
  }

  /// تعديل النتيجة بناءً على التفضيلات الصريحة
  double preferenceAdjustment(String itemId, double score) {
    if (wantsLess(itemId)) return score * 0.3;
    if (wantsMore(itemId)) return score * 1.5;
    return score;
  }

  void clear() {
    _hiddenItems.clear();
    _hiddenCategories.clear();
    _lessLikeThis.clear();
    _moreLikeThis.clear();
  }
}

// ═══════════════════════════════════════════════════════════
// 🧪 القسم 11: A/B Testing Framework
// ═══════════════════════════════════════════════════════════

class ABTestManager {
  final Map<String, _ABTestConfig> _tests = {};
  final String userId;

  ABTestManager(this.userId);

  void registerTest(String name, List<String> variants, Map<String, double> weights) {
    _tests[name] = _ABTestConfig(variants: variants, weights: weights);
  }

  String getVariant(String testName) {
    final config = _tests[testName];
    if (config == null) return 'control';
    // Deterministic hash لضمان اتساق المتغير لنفس المستخدم
    final hash = '${userId}_$testName'.hashCode.abs();
    return config.getVariant(hash);
  }

  bool isInVariant(String testName, String variant) {
    return getVariant(testName) == variant;
  }
}

class _ABTestConfig {
  final List<String> variants;
  final Map<String, double> weights;

  _ABTestConfig({required this.variants, required this.weights});

  String getVariant(int hash) {
    final normalized = (hash % 1000) / 1000.0;
    double cumulative = 0.0;
    for (final variant in variants) {
      cumulative += weights[variant] ?? (1.0 / variants.length);
      if (normalized < cumulative) return variant;
    }
    return variants.last;
  }
}

// ═══════════════════════════════════════════════════════════
// 🛡️ القسم 12: Circuit Breaker
// ═══════════════════════════════════════════════════════════

class CircuitBreaker {
  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  DateTime? _lastFailure;
  final int failureThreshold;
  final Duration resetTimeout;

  CircuitBreaker({
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(minutes: 1),
  });

  Future<T> execute<T>(Future<T> Function() operation, T fallback) async {
    if (_state == CircuitState.open) {
      if (DateTime.now().difference(_lastFailure!) > resetTimeout) {
        _state = CircuitState.halfOpen;
      } else {
        return fallback;
      }
    }

    try {
      final result = await operation();
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure();
      return fallback;
    }
  }

  void _onSuccess() {
    _failureCount = 0;
    _state = CircuitState.closed;
  }

  void _onFailure() {
    _failureCount++;
    _lastFailure = DateTime.now();
    if (_failureCount >= failureThreshold) {
      _state = CircuitState.open;
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 🚀 القسم 13: BeastUltimateV2 - المحرك الرئيسي
// ═══════════════════════════════════════════════════════════

class BeastUltimateV2 {
  static final BeastUltimateV2 _instance = BeastUltimateV2._internal();
  factory BeastUltimateV2() => _instance;
  BeastUltimateV2._internal();

  // المكونات
  final BeastBrainV2 brain = BeastBrainV2();
  final BeastBanditV2 bandit = BeastBanditV2();
  final UserControls userControls = UserControls();
  final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();
  final Queue<Breadcrumb> _breadcrumbs = Queue();
  final StreamController<Map<String, dynamic>> _eventsController =
      StreamController<Map<String, dynamic>>.broadcast();

  // الإعدادات
  BeastConfigV2 _config = const BeastConfigV2();
  ABTestManager? _abTest;
  late ColdStartHandler _coldStart;
  late CircuitBreaker _circuitBreaker;

  Database? _db;
  http.Client? _http;
  FlutterLocalNotificationsPlugin? _notifications;
  StreamSubscription? _networkSub;
  Timer? _flushTimer;
  Timer? _modelTimer;

  // الحالة
  BeastConsentV2 _consent = BeastConsentV2.notDetermined;
  String _userId = 'anonymous';
  String _sessionId = '';
  String _screen = 'unknown';
  String _modelVersion = 'edge-0';
  double _explorationRate = 0.15;

  int _sessionStartedAt = 0;
  int _screenStartedAt = 0;
  int _lastActivityAt = 0;
  ConnectivityResult _network = ConnectivityResult.none;

  bool _ready = false;
  bool _flushing = false;
  bool _syncing = false;
  bool _modelSyncing = false;
  bool _frameActive = false; // ✅ إصلاح Memory Leak

  DateTime? _lastFrame;
  int _frames = 0;
  int _jankFrames = 0;

  // Getters
  BeastConsentV2 get consent => _consent;
  bool get ready => _ready;
  bool get analyticsEnabled => _consent == BeastConsentV2.granted;
  String get sessionId => _sessionId;
  String get modelVersion => _modelVersion;
  Stream<Map<String, dynamic>> get eventStream => _eventsController.stream;

  // ═══════════════════════════════════════════════════════
  // 🏁 التهيئة
  // ═══════════════════════════════════════════════════════

  Future<void> init({
    required String userId,
    BeastConfigV2? config,
  }) async {
    if (_ready) return;

    _config = config ?? _config;
    _userId = userId.trim().isEmpty ? 'anonymous' : userId;
    _http = http.Client();
    _coldStart = ColdStartHandler(_config);
    _circuitBreaker = CircuitBreaker();
    _abTest = ABTestManager(_userId);

    // تسجيل تجارب A/B الافتراضية
    _abTest!.registerTest(
      'ranking_algorithm',
      ['linear', 'ftrl', 'hybrid'],
      {'linear': 0.2, 'ftrl': 0.5, 'hybrid': 0.3},
    );
    _abTest!.registerTest(
      'diversity_lambda',
      ['low', 'medium', 'high'],
      {'low': 0.3, 'medium': 0.5, 'high': 0.2},
    );

    await _openDb();
    await _loadMetaState();
    await _initNotifications();
    if (_config.enableCrashTracking) _initCrashTracking();

    final now = DateTime.now().millisecondsSinceEpoch;
    _sessionId = _generateId();
    _sessionStartedAt = now;
    _screenStartedAt = now;
    _lastActivityAt = now;

    _ready = true;

    if (_config.autoNetwork) await _initNetwork();
    if (_config.autoLifecycle) {
      WidgetsBinding.instance.addObserver(_Lifecycle(this));
    }
    if (_config.autoPerformance) _startFrames();
    if (_config.enableGestureTracking) _initGestureTracking();

    _flushTimer = Timer.periodic(_config.flushInterval, (_) => flush());
    _modelTimer = Timer.periodic(_config.modelSyncInterval, (_) => syncModel());

    if (analyticsEnabled) {
      brain.decay();
      await _writeEvent('session_start', {
        'session_id': _sessionId,
        'model_version': _modelVersion,
      }, priority: 3);
      await syncModel();
    }
  }

  NavigatorObserver get navigatorObserver => _BeastNavigatorObserver(this);

  Future<void> setConsent(BeastConsentV2 value) async {
    _consent = value;
    await _saveMeta('consent', value.name);
    if (value == BeastConsentV2.granted) {
      await _writeEvent('session_start', {
        'session_id': _sessionId,
        'model_version': _modelVersion,
      }, priority: 3);
    } else if (value == BeastConsentV2.denied) {
      await _eraseAll();
    }
  }

  // ═══════════════════════════════════════════════════════
  // 📊 التتبع
  // ═══════════════════════════════════════════════════════

  /// إضافة Breadcrumb (للـ Crash Analysis)
  void addBreadcrumb(String event, [Map<String, dynamic>? data]) {
    _breadcrumbs.addLast(Breadcrumb(event: event, data: data ?? {}));
    while (_breadcrumbs.length > _config.maxBreadcrumbs) {
      _breadcrumbs.removeFirst();
    }
  }

  Future<void> screen(String name) async {
    if (!_allowed()) return;
    final next = name.trim();
    if (next.isEmpty || next == _screen) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_screenStartedAt > 0) {
      await _writeEvent('screen_exit', {
        'screen': _screen,
        'duration_ms': max(0, now - _screenStartedAt),
      });
    }

    _screen = next;
    _screenStartedAt = now;
    _lastActivityAt = now;
    _cache.clear();
    addBreadcrumb('screen_view', {'screen': next});
    await _writeEvent('screen_view', {'screen': next});
  }

  Future<void> impression({
    required String itemId,
    List<String> tags = const [],
    int position = 0,
    String source = 'unknown',
  }) async {
    if (!_allowed()) return;
    final interaction = BeastInteraction(
      itemId: itemId,
      eventType: 'impression',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      tags: tags,
      reward: 0.02,
      context: {'position': position, 'source': source},
    );
    brain.ingest(interaction);
    addBreadcrumb('impression', {'item_id': itemId});
    await _writeEvent('content_impression', {
      'content_id': itemId,
      'tags': tags,
      'position': position,
      'source': source,
    });
  }

  Future<void> openContent({
    required String itemId,
    List<String> tags = const [],
    String? category,
    int position = 0,
    String source = 'unknown',
  }) async {
    if (!_allowed()) return;
    final interaction = BeastInteraction(
      itemId: itemId,
      eventType: 'open',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      tags: tags,
      reward: 1.2,
      context: {'screen': _screen, 'source': source, 'category': category},
    );
    brain.ingest(interaction);
    bandit.update(itemId, 0.7);
    addBreadcrumb('open', {'item_id': itemId});

    await _recordExperience(
      itemId: itemId,
      eventType: 'open',
      reward: 1.0,
      prediction: brain.predict(tags),
      position: position,
      features: _tagVector(tags),
      context: interaction.context,
    );
    await _writeEvent('content_open', {
      'content_id': itemId,
      'tags': tags,
      'position': position,
      'source': source,
    }, priority: 2);
    _cache.clear();
  }

  Future<void> duration({
    required String itemId,
    required int durationMs,
    List<String> tags = const [],
  }) async {
    if (!_allowed() || durationMs <= 0) return;
    final seconds = durationMs / 1000.0;
    final reward = min(1.0, log(1 + seconds) / log(121));
    final interaction = BeastInteraction(
      itemId: itemId,
      eventType: 'dwell',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      tags: tags,
      reward: 3.0 * reward,
      context: {'duration_ms': durationMs},
    );
    brain.ingest(interaction);
    bandit.update(itemId, reward);
    addBreadcrumb('dwell', {'item_id': itemId, 'duration_ms': durationMs});

    await _recordExperience(
      itemId: itemId,
      eventType: 'dwell',
      reward: reward,
      prediction: brain.predict(tags),
      position: 0,
      features: _tagVector(tags),
      context: interaction.context,
    );
    await _writeEvent('content_duration', {
      'content_id': itemId,
      'duration_ms': durationMs,
      'tags': tags,
    });
    _cache.clear();
  }

  Future<void> reaction({
    required String itemId,
    required String reaction,
    List<String> tags = const [],
  }) async {
    if (!_allowed()) return;
    final positive = {'like', 'love', 'save', 'share', 'purchase'}.contains(reaction);
    final reward = positive ? 1.0 : -1.0;
    final interaction = BeastInteraction(
      itemId: itemId,
      eventType: positive ? 'positive' : 'negative',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      tags: tags,
      reward: positive ? 5.0 : -6.0,
      context: {'reaction': reaction},
    );
    brain.ingest(interaction);
    bandit.update(itemId, reward);
    addBreadcrumb('reaction', {'item_id': itemId, 'reaction': reaction});

    await _recordExperience(
      itemId: itemId,
      eventType: positive ? 'positive' : 'negative',
      reward: reward,
      prediction: brain.predict(tags),
      position: 0,
      features: _tagVector(tags),
      context: interaction.context,
    );
    await _writeEvent('content_reaction', {
      'content_id': itemId,
      'reaction': reaction,
      'positive': positive,
      'tags': tags,
    }, priority: 2);
    _cache.clear();
  }

  Future<void> button(String name, {Map<String, dynamic>? extra}) async {
    addBreadcrumb('button', {'name': name});
    await _writeEvent('button_click', {
      'button': name,
      ...?_sanitize(extra ?? {}),
    });
  }

  Future<void> search(String query) async {
    if (!_allowed()) return;
    final q = query.trim();
    addBreadcrumb('search', {'query': q});
    await _writeEvent('search', {
      'query_length': q.length,
      'token_count': q.isEmpty ? 0 : q.split(RegExp(r'\s+')).length.clamp(0, 40),
    });
  }

  Future<void> comment({required String itemId, required String text}) async {
    if (!_allowed()) return;
    addBreadcrumb('comment', {'item_id': itemId});
    await _writeEvent('comment_created', {
      'content_id': itemId,
      'text_length': text.characters.length,
      'has_text': text.trim().isNotEmpty,
    }, priority: 2);
    bandit.update(itemId, 0.9);
  }

  Future<void> purchase({
    required String itemId,
    required double price,
    List<String> tags = const [],
  }) async {
    if (!_allowed()) return;
    final interaction = BeastInteraction(
      itemId: itemId,
      eventType: 'purchase',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      tags: tags,
      reward: 10.0,
      context: {'price': price},
    );
    brain.ingest(interaction);
    bandit.update(itemId, 1.0);
    addBreadcrumb('purchase', {'item_id': itemId, 'price': price});

    await _recordExperience(
      itemId: itemId,
      eventType: 'purchase',
      reward: 1.0,
      prediction: brain.predict(tags),
      position: 0,
      features: _tagVector(tags),
      context: interaction.context,
    );
    await _writeEvent('purchase', {
      'item_id': itemId,
      'price': price,
      'tags': tags,
    }, priority: 3);
    _cache.clear();
  }

  // ═══════════════════════════════════════════════════════
  // 🎯 نظام التوصيات المتقدم
  // ═══════════════════════════════════════════════════════

  Future<List<BeastRecommendationV2>> recommend(
    List<BeastCandidateV2> candidates, {
    required String context,
    int limit = 20,
    bool allowServer = true,
  }) async {
    if (!_allowed() || candidates.isEmpty) return [];
    await _ensureSession();

    // ✅ تصفية العناصر المرفوضة من المستخدم
    final filtered = userControls.filter(candidates);
    if (filtered.isEmpty) return [];

    // Cache Key محسّن باستخدام SHA-256
    final cacheKey = _buildCacheKey(context, filtered);
    final cached = _cache[cacheKey];
    if (cached != null && !cached.expired(const Duration(minutes: 3))) {
      _moveToFront(cacheKey);
      return cached.items.take(limit).toList();
    }

    // Cold Start Check
    if (_coldStart.isColdStart(brain)) {
      final coldResults = _coldStart.generate(filtered, limit);
      _cache[cacheKey] = _CacheEntry(coldResults, DateTime.now());
      await _writeEvent('recommendation_served', {
        'context': context,
        'strategy': 'cold_start',
        'count': coldResults.length,
      });
      return coldResults;
    }

    // Session Intent Detection
    final intent = SessionIntentDetector.detect(brain);

    // ✅ الحصول على متغير A/B Test الحالي
    final algorithm = _abTest!.getVariant('ranking_algorithm');
    final diversityVariant = _abTest!.getVariant('diversity_lambda');
    final diversityLambda = diversityVariant == 'high' ? 0.8 :
                           diversityVariant == 'low' ? 0.5 : 0.7;

    // Multi-Signal Scoring
    final ranked = filtered.map((c) {
      final affinity = brain.tagAffinity(c.tags);
      final mlPrediction = brain.predict(c.tags);
      final ctr = brain.ctr(c.itemId);
      final exposure = brain.impressions[c.itemId] ?? 0;
      final base = _featureScore(c.features);

      // Thompson Sampling مع exploration rate قابل للتعديل
      final banditSample = bandit.sample(c.itemId);
      final exploreProb = exposure < 5 ? min(0.5, _explorationRate * 2) : _explorationRate;
      final explore = Random.secure().nextDouble() < exploreProb;
      final exploration = explore ? banditSample * 0.18 : 0.0;

      // Time & Session Awareness
      final timeBoost = TimeAwareness.timeBoost(c);
      final intentBoost = SessionIntentDetector.intentBoost(intent, c);

      // Multi-Objective Score
      var score = base +
          _squash(affinity) * 2.4 +
          mlPrediction * 1.8 +
          ctr * 1.1 -
          min(exposure * 0.008, 0.45) +
          exploration +
          timeBoost +
          intentBoost;

      // User Preference Adjustment
      score = userControls.preferenceAdjustment(c.itemId, score);

      // Signals Map للـ Explainability
      final signals = {
        'base': base,
        'affinity': affinity,
        'ml_prediction': mlPrediction,
        'ctr': ctr,
        'bandit': banditSample,
        'exploration': exploration,
        'exposure': exposure.toDouble(),
        'time_boost': timeBoost,
        'intent_boost': intentBoost,
      };

      return BeastRecommendationV2(
        itemId: c.itemId,
        score: score,
        confidence: _confidence(exposure),
        strategy: explore ? RecStrategy.exploration : RecStrategy.personalized,
        source: RecSource.edge,
        signals: signals,
        metadata: {
          ...c.metadata,
          'category': c.category,
          'tags': c.tags,
          'explored': explore,
          'model_version': _modelVersion,
          'intent': intent.name,
        },
        reason: ExplainableAI.generateReason(c, signals, explore),
        abTestVariant: algorithm,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    // MMR Diversity
    var result = _applyDiversity(ranked, min(limit, ranked.length), diversityLambda);

    // Server Fallback (مع Circuit Breaker)
    if (allowServer && result.length < limit) {
      final remote = await _circuitBreaker.execute(
        () => _fetchServer(context, limit),
        <BeastRecommendationV2>[],
      );
      result = _merge(result, remote).take(limit).toList();
    }

    _cache[cacheKey] = _CacheEntry(result, DateTime.now());
    _trimCache();

    await _writeEvent('recommendation_served', {
      'context': context,
      'count': result.length,
      'model_version': _modelVersion,
      'ab_variant': algorithm,
      'intent': intent.name,
      'items': result.take(20).map((e) => e.toJson()).toList(),
    });

    return result;
  }

  // ═══════════════════════════════════════════════════════
  // 🌐 مزامنة الخادم
  // ═══════════════════════════════════════════════════════

  Future<void> syncExperiences() async {
    if (!_allowed() || _syncing || _db == null || _http == null) return;
    _syncing = true;
    try {
      final rows = await _db!.query(
        'experiences',
        where: 'synced = 0',
        orderBy: 'id ASC',
        limit: 200,
      );
      if (rows.isEmpty) return;

      final response = await _http!.post(
        Uri.parse('${_config.serverUrl}/v2/beast/experience/batch'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'user_id': _userId,
          'session_id': _sessionId,
          'model_version': _modelVersion,
          'experiences': rows,
          'user_brain': brain.snapshot(),
        }),
      ).timeout(_config.requestTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final ids = rows.map((e) => e['id']).toList();
        final placeholders = List.filled(ids.length, '?').join(',');
        await _db!.rawUpdate(
          'UPDATE experiences SET synced = 1 WHERE id IN ($placeholders)',
          ids,
        );
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['model_update_available'] == true) {
          await syncModel();
        }
      }
    } catch (e) {
      debugPrint('Beast experience sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<void> syncModel() async {
    if (!_allowed() || _modelSyncing || _http == null) return;
    _modelSyncing = true;
    try {
      final response = await _http!.get(
        Uri.parse('${_config.serverUrl}/v2/beast/model'),
        headers: {'Accept': 'application/json'},
      ).timeout(_config.requestTimeout);

      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      if (data is! Map) return;

      if (data['model_version'] != null) {
        _modelVersion = data['model_version'].toString();
        await _saveMeta('model_version', _modelVersion);
      }
      if (data['exploration_rate'] is num) {
        _explorationRate = (data['exploration_rate'] as num).toDouble().clamp(0.01, 0.5);
        await _saveMeta('exploration_rate', '$_explorationRate');
      }
      final banditData = data['bandit'];
      if (banditData is Map) {
        this.bandit.importState(Map<String, dynamic>.from(banditData));
        await _saveMeta('bandit', jsonEncode(this.bandit.exportState()));
      }
      addBreadcrumb('model_sync', {'version': _modelVersion});
      await _writeEvent('model_sync', {'model_version': _modelVersion});
    } catch (e) {
      debugPrint('Beast model sync failed: $e');
    } finally {
      _modelSyncing = false;
    }
  }

  Future<void> flush() async {
    if (!_allowed() || _flushing || _db == null || _http == null) return;
    _flushing = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rows = await _db!.query(
        'events',
        where: 'next_retry_at <= ?',
        whereArgs: [now],
        orderBy: 'priority DESC, id ASC',
        limit: _config.batchSize,
      );
      if (rows.isEmpty) return;

      final events = <Map<String, dynamic>>[];
      final ids = <int>[];
      for (final row in rows) {
        try {
          final decoded = jsonDecode(row['payload'] as String);
          if (decoded is Map) {
            events.add(Map<String, dynamic>.from(decoded));
            ids.add(row['id'] as int);
          }
        } catch (_) {
          await _db!.delete('events', where: 'id = ?', whereArgs: [row['id']]);
        }
      }
      if (events.isEmpty) return;

      final body = jsonEncode({
        'user_id': _userId,
        'session_id': _sessionId,
        'breadcrumbs': _breadcrumbs.map((b) => b.toJson()).toList(),
        'events': events,
      });

      final request = http.Request(
        'POST',
        Uri.parse('${_config.serverUrl}/v2/beast/events/batch'),
      )
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'application/json'
        ..headers['Accept-Encoding'] = 'gzip'
        ..body = body;

      if (_config.enableGzip && body.length > 1024) {
        request.bodyBytes = GZipCodec().encode(utf8.encode(body));
        request.headers['Content-Encoding'] = 'gzip';
      }

      final streamedResponse = await _http!.send(request).timeout(_config.requestTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final q = List.filled(ids.length, '?').join(',');
        await _db!.rawDelete('DELETE FROM events WHERE id IN ($q)', ids);
      } else {
        await _retry(rows);
      }
    } catch (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rows = await _db!.query(
        'events',
        where: 'next_retry_at <= ?',
        whereArgs: [now],
        orderBy: 'priority DESC, id ASC',
        limit: _config.batchSize,
      );
      await _retry(rows);
    } finally {
      _flushing = false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 🔄 دورة الحياة
  // ═══════════════════════════════════════════════════════

  Future<void> onForeground() async {
    if (!_allowed()) return;
    await _ensureSession();
    await _writeEvent('app_foreground', {}, priority: 2);
    await syncModel();
  }

  Future<void> onBackground() async {
    if (!_allowed()) return;
    await _writeEvent('app_background', {'session_age_ms': _sessionAgeMs()}, priority: 2);
    await syncExperiences();
    await flush();
  }

  // ═══════════════════════════════════════════════════════
  // 🛠️ أدوات مساعدة
  // ═══════════════════════════════════════════════════════

  Future<int> pendingEvents() async {
    final r = await _db?.rawQuery('SELECT COUNT(*) AS count FROM events') ?? [];
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<int> pendingExperiences() async {
    final r = await _db?.rawQuery('SELECT COUNT(*) AS count FROM experiences WHERE synced = 0') ?? [];
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (_notifications == null) return;
    const androidDetails = AndroidNotificationDetails(
      'beast_channel',
      'Beast Notifications',
      channelDescription: 'Beast application notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: darwinDetails);
    await _notifications!.show(id, title, body, notificationDetails: details, payload: payload);
  }

  /// الحصول على أسباب التوصية (للعرض في UI)
  List<Map<String, dynamic>> getRecommendationReasons(List<BeastRecommendationV2> recs) {
    return recs.map((r) => {
          'item_id': r.itemId,
          'reason': r.reason,
          'confidence': r.confidence,
          'strategy': r.strategy.name,
        }).toList();
  }

  Future<void> dispose() async {
    _frameActive = false; // ✅ إيقاف مراقب الإطارات
    if (_allowed()) {
      await _writeEvent('session_end', {'session_age_ms': _sessionAgeMs()}, priority: 3);
      await syncExperiences();
      await flush();
    }
    _flushTimer?.cancel();
    _modelTimer?.cancel();
    await _networkSub?.cancel();
    await _db?.close();
    _http?.close();
    await _eventsController.close();
    _db = null;
    _http = null;
    _ready = false;
  }

  // ═══════════════════════════════════════════════════════
  // 🏗️ الدوال الداخلية
  // ═══════════════════════════════════════════════════════

  Future<void> _openDb() async {
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'beast_ultimate.db'),
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA journal_mode=WAL'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id TEXT NOT NULL UNIQUE,
            event_type TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            next_retry_at INTEGER NOT NULL DEFAULT 0,
            priority INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('CREATE INDEX idx_events_ready ON events(next_retry_at, priority DESC, id)');
        await db.execute('''
          CREATE TABLE experiences (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            experience_id TEXT NOT NULL UNIQUE,
            item_id TEXT NOT NULL,
            event_type TEXT NOT NULL,
            reward REAL NOT NULL DEFAULT 0,
            prediction REAL NOT NULL DEFAULT 0,
            position INTEGER NOT NULL DEFAULT 0,
            features TEXT NOT NULL,
            context TEXT NOT NULL,
            model_version TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX idx_exp_sync ON experiences(synced, id)');
        await db.execute('''
          CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('CREATE INDEX idx_exp_sync ON experiences(synced, id)');
        }
      },
    );
  }

  Future<void> _loadMetaState() async {
    final consent = await _readMeta('consent');
    if (consent == 'granted') _consent = BeastConsentV2.granted;
    if (consent == 'denied') _consent = BeastConsentV2.denied;
    _modelVersion = await _readMeta('model_version') ?? _modelVersion;
    _explorationRate = double.tryParse(await _readMeta('exploration_rate') ?? '') ?? _explorationRate;
    final banditRaw = await _readMeta('bandit');
    if (banditRaw != null) {
      try {
        final decoded = jsonDecode(banditRaw);
        if (decoded is Map) bandit.importState(Map<String, dynamic>.from(decoded));
      } catch (_) {}
    }
  }

  Future<void> _initNotifications() async {
    _notifications = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: androidSettings, iOS: darwinSettings);
    await _notifications!.initialize(settings: settings);
  }

  void _initCrashTracking() {
    FlutterError.onError = (details) {
      unawaited(_writeEvent('crash', {
        'exception': details.exceptionAsString(),
        'stack': details.stack?.toString(),
        'context': details.context?.toString(),
        'breadcrumbs': _breadcrumbs.map((b) => b.toJson()).toList(),
      }, priority: 3));
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(_writeEvent('crash', {
        'error': error.toString(),
        'stack': stack.toString(),
        'breadcrumbs': _breadcrumbs.map((b) => b.toJson()).toList(),
      }, priority: 3));
      return true;
    };
  }

  void _initGestureTracking() {
    GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
      if (!_allowed()) return;
      if (_config.privacy != BeastPrivacyV2.extensive) return;
      if (event is PointerDownEvent) {
        unawaited(_writeEvent('touch', {
          'position': {'x': event.position.dx, 'y': event.position.dy},
          'timestamp': event.timeStamp.inMicroseconds,
        }, priority: 0));
      }
    });
  }

  Future<void> _writeEvent(String type, Map<String, dynamic> data, {int priority = 1}) async {
    if (!_allowed()) return;
    final db = _db;
    if (db == null) return;

    final event = {
      'event_id': _generateId(),
      'event_type': type,
      'user_id': _userId,
      'session_id': _sessionId,
      'screen': _screen,
      'model_version': _modelVersion,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'network': _network.name,
      'data': _config.enableRedaction ? _redact(_sanitize(data)) : _sanitize(data),
    };
    await db.insert('events', {
      'event_id': event['event_id'],
      'event_type': type,
      'payload': jsonEncode(event),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'retry_count': 0,
      'next_retry_at': 0,
      'priority': priority,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
    await _trimEvents();
  }

  Future<void> _recordExperience({
    required String itemId,
    required String eventType,
    required double reward,
    required double prediction,
    required int position,
    required Map<String, double> features,
    required Map<String, dynamic> context,
  }) async {
    await _db?.insert('experiences', {
      'experience_id': _generateId(),
      'item_id': itemId,
      'event_type': eventType,
      'reward': reward,
      'prediction': prediction,
      'position': position,
      'features': jsonEncode(features),
      'context': jsonEncode(context),
      'model_version': _modelVersion,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'synced': 0,
    });
    await _trimExperiences();
  }

  Future<void> _retry(List<Map<String, Object?>> rows) async {
    final batch = _db!.batch();
    for (final row in rows) {
      final retry = ((row['retry_count'] as int?) ?? 0) + 1;
      if (retry > 8 && (row['priority'] as int? ?? 0) <= 0) {
        batch.delete('events', where: 'id = ?', whereArgs: [row['id']]);
        continue;
      }
      final delay = min(900, pow(2, min(retry, 8)).toInt() + Random.secure().nextInt(8));
      batch.update('events', {
        'retry_count': retry,
        'next_retry_at': DateTime.now().add(Duration(seconds: delay)).millisecondsSinceEpoch,
      }, where: 'id = ?', whereArgs: [row['id']]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> _trimEvents() async {
    final result = await _db!.rawQuery('SELECT COUNT(*) AS count FROM events');
    final count = Sqflite.firstIntValue(result) ?? 0;
    if (count <= _config.maxEvents) return;
    await _db!.delete('events',
        where: 'id IN (SELECT id FROM events ORDER BY priority ASC, id ASC LIMIT ?)',
        whereArgs: [count - _config.maxEvents]);
  }

  Future<void> _trimExperiences() async {
    final result = await _db!.rawQuery('SELECT COUNT(*) AS count FROM experiences');
    final count = Sqflite.firstIntValue(result) ?? 0;
    if (count <= _config.maxExperiences) return;
    await _db!.delete('experiences',
        where: 'id IN (SELECT id FROM experiences ORDER BY synced DESC, id ASC LIMIT ?)',
        whereArgs: [count - _config.maxExperiences]);
  }

  Future<void> _saveMeta(String key, String value) async {
    await _db?.insert('meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> _readMeta(String key) async {
    final rows = await _db?.query('meta', where: 'key = ?', whereArgs: [key], limit: 1) ?? [];
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _eraseAll() async {
    brain.clear();
    userControls.clear();
    _cache.clear();
    _breadcrumbs.clear();
    await _db?.delete('events');
    await _db?.delete('experiences');
    await _db?.delete('meta');
  }

  Future<void> _initNetwork() async {
    try {
      _network = await Connectivity().checkConnectivity();
      _networkSub = Connectivity().onConnectivityChanged.listen((value) async {
        _network = value;
        if (_allowed()) {
          await _writeEvent('network_change', {'type': value.name}, priority: 0);
          if (value != ConnectivityResult.none) {
            await syncExperiences();
            await flush();
          }
        }
      });
    } catch (_) {}
  }

  void _startFrames() {
    _frameActive = true;
    SchedulerBinding.instance.addPostFrameCallback(_frame);
  }

  void _frame(Duration timestamp) {
    if (!_frameActive) return; // ✅ حماية من Memory Leak
    if (_ready && _allowed()) {
      final now = DateTime.now();
      if (_lastFrame != null) {
        final ms = now.difference(_lastFrame!).inMicroseconds / 1000.0;
        if (ms > 32) _jankFrames++;
      }
      _lastFrame = now;
      _frames++;
      if (_frames % 120 == 0) {
        unawaited(_writeEvent('performance', {
          'frames': _frames,
          'jank_frames': _jankFrames,
          'screen': _screen,
        }, priority: 0));
      }
    }
    if (_frameActive) {
      SchedulerBinding.instance.addPostFrameCallback(_frame);
    }
  }

  Future<void> _ensureSession() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastActivityAt > _config.sessionTimeout.inMilliseconds) {
      _sessionId = _generateId();
      _sessionStartedAt = now;
      await _writeEvent('session_start', {'session_id': _sessionId}, priority: 3);
    }
    _lastActivityAt = now;
  }

  int _sessionAgeMs() => max(0, DateTime.now().millisecondsSinceEpoch - _sessionStartedAt);

  Future<List<BeastRecommendationV2>> _fetchServer(String context, int limit) async {
    if (_http == null) return [];
    try {
      final response = await _http!.post(
        Uri.parse('${_config.serverUrl}/v2/beast/recommend'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'user_id': _userId,
          'session_id': _sessionId,
          'model_version': _modelVersion,
          'context': {
            'screen': _screen,
            'hour': DateTime.now().hour,
            'weekday': DateTime.now().weekday,
            'session_age_sec': _sessionAgeMs() ~/ 1000,
            'network': _network.name,
            'local_memory': brain.snapshot(),
          },
          'limit': limit,
        }),
      ).timeout(_config.requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) return [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['items'] is! List) return [];

      return (decoded['items'] as List).whereType<Map>().map((e) {
        return BeastRecommendationV2(
          itemId: e['item_id']?.toString() ?? '',
          score: (e['score'] as num?)?.toDouble() ?? 0,
          confidence: (e['confidence'] as num?)?.toDouble() ?? 0.5,
          strategy: RecStrategy.personalized,
          source: RecSource.server,
          signals: const {},
          metadata: e['metadata'] is Map ? Map<String, dynamic>.from(e['metadata']) : const {},
          reason: e['reason']?.toString() ?? 'مُختار من الخادم',
        );
      }).where((e) => e.itemId.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  List<BeastRecommendationV2> _merge(List<BeastRecommendationV2> a, List<BeastRecommendationV2> b) {
    final map = <String, BeastRecommendationV2>{for (final x in a) x.itemId: x};
    for (final x in b) {
      final old = map[x.itemId];
      if (old == null || x.score > old.score) map[x.itemId] = x;
    }
    return map.values.toList()..sort((x, y) => y.score.compareTo(x.score));
  }

  /// MMR Diversity Engine (Maximal Marginal Relevance)
  List<BeastRecommendationV2> _applyDiversity(
    List<BeastRecommendationV2> input,
    int topK,
    double lambda,
  ) {
    if (input.length <= topK) return input.take(topK).toList();

    final remaining = [...input];
    final selected = <BeastRecommendationV2>[];

    while (selected.length < topK && remaining.isNotEmpty) {
      BeastRecommendationV2? best;
      double bestScore = double.negativeInfinity;

      for (final candidate in remaining) {
        double maxSim = 0;
        for (final chosen in selected) {
          final ca = candidate.metadata['category']?.toString();
          final cb = chosen.metadata['category']?.toString();
          if (ca != null && cb != null && ca == cb) maxSim = max(maxSim, 1.0);

          // Tag overlap similarity
          final tagsA = (candidate.metadata['tags'] as List?)?.cast<String>() ?? [];
          final tagsB = (chosen.metadata['tags'] as List?)?.cast<String>() ?? [];
          if (tagsA.isNotEmpty && tagsB.isNotEmpty) {
            final intersection = tagsA.toSet().intersection(tagsB.toSet()).length;
            final union = tagsA.toSet().union(tagsB.toSet()).length;
            final tagSim = intersection / union;
            maxSim = max(maxSim, tagSim * 0.5);
          }
        }
        final mmr = lambda * candidate.score - (1 - lambda) * maxSim;
        if (mmr > bestScore) {
          bestScore = mmr;
          best = candidate;
        }
      }
      if (best == null) break;
      selected.add(best);
      remaining.remove(best);
    }
    return selected;
  }

  double _featureScore(Map<String, double> features) {
    const weights = {
      'quality': 0.8,
      'popularity': 0.35,
      'recency': 0.55,
      'novelty': 0.25,
      'creator_affinity': 0.9,
      'category_affinity': 1.0,
      'session_affinity': 0.85,
    };
    var score = 0.0;
    for (final e in features.entries) {
      score += (weights[e.key] ?? 0.1) * e.value;
    }
    return score;
  }

  Map<String, double> _tagVector(List<String> tags) => {
        for (final tag in tags) 'tag:${tag.trim().toLowerCase()}': 1.0,
      };

  double _confidence(int impressions) => (1 - 1 / sqrt(impressions + 2)).clamp(0.15, 0.95);

  double _squash(double x) => tanh(x / 5);

  Map<String, dynamic> _sanitize(Map<String, dynamic> data) {
    final output = <String, dynamic>{};
    for (final e in data.entries) {
      final key = e.key.toLowerCase();
      if ({
        'password', 'token', 'authorization', 'access_token',
        'refresh_token', 'secret', 'private_key', 'message_body', 'raw_text'
      }.contains(key)) {
        continue;
      }
      final v = e.value;
      if (v == null || v is num || v is bool || v is String) {
        output[e.key] = v;
      } else if (v is List) {
        output[e.key] = v.take(50).toList();
      } else if (v is Map) {
        output[e.key] = _sanitize(Map<String, dynamic>.from(v));
      }
    }
    return output;
  }

  /// تنقيح البيانات الحساسة (Redaction)
  Map<String, dynamic> _redact(Map<String, dynamic> data) {
    final redacted = <String, dynamic>{};
    final sensitiveKeys = [
      'email', 'phone', 'address', 'credit_card', 'ssn',
      'passport', 'national_id', 'bank_account',
    ];

    data.forEach((key, value) {
      final keyLower = key.toLowerCase();
      if (sensitiveKeys.any((s) => keyLower.contains(s))) {
        redacted[key] = '[REDACTED]';
      } else if (value is Map) {
        redacted[key] = _redact(Map<String, dynamic>.from(value));
      } else if (value is String && _looksLikePII(value)) {
        redacted[key] = '[REDACTED]';
      } else {
        redacted[key] = value;
      }
    });
    return redacted;
  }

  bool _looksLikePII(String value) {
    if (value.contains('@') && value.contains('.')) return true;
    if (RegExp(r'^\+?[\d\s-]{10,}$').hasMatch(value)) return true;
    return false;
  }

  String _generateId() => '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  bool _allowed() => _ready && _consent == BeastConsentV2.granted;

  String _buildCacheKey(String context, List<BeastCandidateV2> candidates) {
    final candidateIds = candidates.map((e) => e.itemId).toList()..sort();
    final hashInput = '$context|${candidateIds.join(",")}|$_modelVersion';
    final hash = sha256.convert(utf8.encode(hashInput)).toString();
    return hash.substring(0, 32);
  }

  void _moveToFront(String key) {
    final value = _cache.remove(key);
    if (value != null) _cache[key] = value;
  }

  void _trimCache() {
    while (_cache.length > 80) {
      _cache.remove(_cache.keys.first);
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 🧭 مراقب التنقل
// ═══════════════════════════════════════════════════════════

class _BeastNavigatorObserver extends NavigatorObserver {
  final BeastUltimateV2 beast;
  _BeastNavigatorObserver(this.beast);

  String _routeName(Route<dynamic>? route) {
    final name = route?.settings.name;
    return name == null || name.isEmpty ? (route?.runtimeType.toString() ?? 'unknown') : name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    unawaited(beast.screen(_routeName(route)));
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    unawaited(beast.screen(_routeName(previousRoute)));
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    unawaited(beast.screen(_routeName(newRoute)));
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

// ═══════════════════════════════════════════════════════════
// 🔄 مراقب دورة الحياة
// ═══════════════════════════════════════════════════════════

class _Lifecycle with WidgetsBindingObserver {
  final BeastUltimateV2 beast;
  _Lifecycle(this.beast);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(beast.onForeground());
        break;
      case AppLifecycleState.paused:
        unawaited(beast.onBackground());
        break;
      case AppLifecycleState.detached:
        unawaited(beast.dispose());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 💾 Cache Entry
// ═══════════════════════════════════════════════════════════

class _CacheEntry {
  final List<BeastRecommendationV2> items;
  final DateTime createdAt;
  const _CacheEntry(this.items, this.createdAt);
  bool expired(Duration ttl) => DateTime.now().difference(createdAt) > ttl;
}

/*
USAGE EXAMPLES (documentation only — not executable top-level code):

  // عند عرض عنصر
  await BeastUltimateV2().impression(
    itemId: 'video_123',
    tags: ['cooking', 'italian'],
    position: 0,
    source: 'home_feed',
  );

  // عند فتح عنصر
  await BeastUltimateV2().openContent(
    itemId: 'video_123',
    tags: ['cooking', 'italian'],
    category: 'food',
  );

  // عند قضاء وقت
  await BeastUltimateV2().duration(
    itemId: 'video_123',
    durationMs: 45000,
    tags: ['cooking', 'italian'],
  );

  // عند الشراء
  await BeastUltimateV2().purchase(
    itemId: 'product_123',
    price: 29.99,
    tags: ['electronics'],
  );

  // عند إخفاء عنصر
  BeastUltimateV2().userControls.hideItem('video_123');
  BeastUltimateV2().userControls.hideCategory('news');
  BeastUltimateV2().userControls.lessLikeThis('video_456');
  BeastUltimateV2().userControls.moreLikeThis('video_789');

  BeastUltimateV2().eventStream.listen((event) {
    print('حدث جديد: ${event['event_type']}');
    // يمكنك إرسال الأحداث لتطبيقات أخرى (Analytics)
  });

  // إضافة breadcrumb قبل كل إجراء مهم
  BeastUltimateV2().addBreadcrumb('user_login', {'method': 'google'});
  BeastUltimateV2().addBreadcrumb('api_call', {'endpoint': '/videos'});
  BeastUltimateV2().addBreadcrumb('error_state', {'code': 500});

  // عند الانهيار، سيتم إرسال آخر 50 breadcrumb تلقائياً للخادم

NOTE: the pubspec.yaml `dependencies:` block that used to be pasted here
does NOT belong in a .dart file. Add it to your project's pubspec.yaml
instead:

  dependencies:
    flutter:
      sdk: flutter
    sqflite: ^2.3.0
    path: ^1.8.3
    http: ^1.1.0
    connectivity_plus: ^5.0.2
    flutter_local_notifications: ^16.3.0
*/

