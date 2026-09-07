// lib/core/beast/beast_forgetting.dart

import 'dart:math' as math;

/// حالة ذاكرة عنصر/موضوع داخل Beast.
///
/// القوة تمثل مدى ترسخ الإشارة.
/// آخر مراجعة تستخدم لحساب مقدار الاضمحلال مع الزمن.
class BeastMemoryTrace {
  BeastMemoryTrace({
    required this.key,
    this.strength = 1.0,
    DateTime? lastUpdated,
    this.positiveEvidence = 0.0,
    this.negativeEvidence = 0.0,
    this.reviewCount = 0,
  }) : lastUpdated =
          lastUpdated ?? DateTime.now();

  final String key;

  double strength;
  DateTime lastUpdated;

  double positiveEvidence;
  double negativeEvidence;

  int reviewCount;

  double get netEvidence =>
      positiveEvidence -
      negativeEvidence;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'key': key,
      'strength': strength,
      'last_updated':
          lastUpdated.toUtc().toIso8601String(),
      'positive_evidence':
          positiveEvidence,
      'negative_evidence':
          negativeEvidence,
      'review_count':
          reviewCount,
    };
  }

  factory BeastMemoryTrace.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawDate =
        json['last_updated'];

    final parsedDate =
        rawDate is String
            ? DateTime.tryParse(rawDate)
            : null;

    return BeastMemoryTrace(
      key: json['key']?.toString() ?? '',
      strength:
          _safeDouble(
        json['strength'],
        fallback: 1.0,
      ),
      lastUpdated:
          parsedDate ?? DateTime.now(),
      positiveEvidence:
          _safeDouble(
        json['positive_evidence'],
      ),
      negativeEvidence:
          _safeDouble(
        json['negative_evidence'],
      ),
      reviewCount:
          _safeInt(
        json['review_count'],
      ),
    );
  }

  static double _safeDouble(
    Object? value, {
    double fallback = 0.0,
  }) {
    if (value is num) {
      final result = value.toDouble();
      return result.isFinite ? result : fallback;
    }
    return fallback;
  }

  static int _safeInt(
    Object? value,
  ) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}

/// محرك النسيان التكيفي.
///
/// الفكرة:
/// - الإشارة الجديدة لا تمحو القديمة مباشرة.
/// - القوة تتراكم مع الأدلة.
/// - الزمن يسبب decay.
/// - التفاعل القوي يعيد تثبيت الذاكرة.
/// - الذكريات القديمة جدًا تصبح أضعف، لكنها لا تختفي
///   إلا عندما نقرر حذفها وفق threshold.
class BeastAdaptiveForgetting {
  BeastAdaptiveForgetting({
    this.baseHalfLife =
        const Duration(days: 14),
    this.minimumRetention = 0.02,
    this.maximumStrength = 10.0,
    this.reviewBoost = 0.20,
    this.negativePenalty = 0.18,
  });

  /// نصف عمر افتراضي للذاكرة.
  ///
  /// سيتم لاحقًا تخصيصه لكل نوع من الإشارات.
  final Duration baseHalfLife;

  /// أقل Retention قبل اعتبار الذاكرة شبه منسية.
  final double minimumRetention;

  final double maximumStrength;

  /// مقدار تعزيز الذاكرة عند دليل إيجابي.
  final double reviewBoost;

  /// مقدار خفض الذاكرة عند دليل سلبي.
  final double negativePenalty;

  final Map<String, BeastMemoryTrace>
      _traces =
      <String, BeastMemoryTrace>{};

  Map<String, BeastMemoryTrace>
      get traces =>
          Map.unmodifiable(_traces);

  // ---------------------------------------------------------------------------
  // LOOKUP
  // ---------------------------------------------------------------------------

  BeastMemoryTrace? trace(
    String key,
  ) {
    final normalized =
        _normalize(key);

    if (normalized.isEmpty) {
      return null;
    }

    return _traces[normalized];
  }

  double retention(
    String key, {
    DateTime? now,
  }) {
    final trace =
        this.trace(key);

    if (trace == null) {
      return 0.0;
    }

    return retentionForTrace(
      trace,
      now: now,
    );
  }

  double retentionForTrace(
    BeastMemoryTrace trace, {
    DateTime? now,
  }) {
    final current =
        now ?? DateTime.now();

    final elapsed =
        current.difference(
          trace.lastUpdated,
        );

    if (elapsed.isNegative) {
      return 1.0;
    }

    final halfLifeMs =
        math.max(
      1.0,
      baseHalfLife.inMilliseconds
          .toDouble(),
    );

    final elapsedMs =
        elapsed.inMilliseconds
            .toDouble();

    final decay =
        math.pow(
          0.5,
          elapsedMs / halfLifeMs,
        );

    final raw =
        trace.strength * decay;

    return raw.clamp(
      0.0,
      1.0,
    );
  }

  // ---------------------------------------------------------------------------
  // LEARNING
  // ---------------------------------------------------------------------------

  void reinforce(
    String key, {
    double evidence = 1.0,
    double weight = 1.0,
    DateTime? now,
  }) {
    final normalized =
        _normalize(key);

    if (normalized.isEmpty) {
      return;
    }

    final current =
        _traces.putIfAbsent(
      normalized,
      () => BeastMemoryTrace(
        key: normalized,
      ),
    );

    final safeEvidence =
        evidence.isFinite
            ? evidence.abs()
            : 0.0;

    final safeWeight =
        weight.isFinite
            ? weight.clamp(0.0, 4.0)
            : 1.0;

    final previousRetention =
        retentionForTrace(
      current,
      now: now,
    );

    final boost =
        reviewBoost *
        safeEvidence *
        safeWeight;

    current.strength =
        (current.strength *
                math.max(
                  0.25,
                  previousRetention,
                ) +
            boost)
        .clamp(
      0.0,
      maximumStrength,
    );

    current.positiveEvidence +=
        safeEvidence *
            safeWeight;

    current.reviewCount += 1;
    current.lastUpdated =
        now ?? DateTime.now();
  }

  void penalize(
    String key, {
    double evidence = 1.0,
    double weight = 1.0,
    DateTime? now,
  }) {
    final normalized =
        _normalize(key);

    if (normalized.isEmpty) {
      return;
    }

    final current =
        _traces.putIfAbsent(
      normalized,
      () => BeastMemoryTrace(
        key: normalized,
      ),
    );

    final safeEvidence =
        evidence.isFinite
            ? evidence.abs()
            : 0.0;

    final safeWeight =
        weight.isFinite
            ? weight.clamp(0.0, 4.0)
            : 1.0;

    final previousRetention =
        retentionForTrace(
      current,
      now: now,
    );

    final penalty =
        negativePenalty *
        safeEvidence *
        safeWeight;

    current.strength =
        (current.strength *
                math.max(
                  0.15,
                  previousRetention,
                ) -
            penalty)
        .clamp(
      0.0,
      maximumStrength,
    );

    current.negativeEvidence +=
        safeEvidence *
            safeWeight;

    current.reviewCount += 1;
    current.lastUpdated =
        now ?? DateTime.now();
  }

  void review(
    String key, {
    required double engagement,
    DateTime? now,
  }) {
    final safe =
        engagement.isFinite
            ? engagement.clamp(-1.0, 1.0)
            : 0.0;

    if (safe > 0) {
      reinforce(
        key,
        evidence: safe,
        now: now,
      );
      return;
    }

    if (safe < 0) {
      penalize(
        key,
        evidence: safe.abs(),
        now: now,
      );
      return;
    }

    final normalized =
        _normalize(key);

    final existing =
        _traces[normalized];

    if (existing != null) {
      existing.lastUpdated =
          now ?? DateTime.now();
      existing.reviewCount += 1;
    }
  }

  // ---------------------------------------------------------------------------
  // DECAY
  // ---------------------------------------------------------------------------

  void applyDecay({
    DateTime? now,
  }) {
    final current =
        now ?? DateTime.now();

    for (final trace
        in _traces.values) {
      final retention =
          retentionForTrace(
        trace,
        now: current,
      );

      trace.strength =
          trace.strength *
              retention.clamp(
                0.0,
                1.0,
              );

      trace.strength =
          trace.strength.clamp(
        0.0,
        maximumStrength,
      );
    }
  }

  /// يحذف الذكريات التي أصبحت غير مفيدة فعليًا.
  ///
  /// الإزالة لا تتم بمجرد مرور الوقت؛
  /// يجب أن تكون الإشارة ضعيفة جدًا.
  int prune({
    DateTime? now,
  }) {
    final current =
        now ?? DateTime.now();

    final toRemove =
        <String>[];

    for (final entry
        in _traces.entries) {
      final retention =
          retentionForTrace(
        entry.value,
        now: current,
      );

      final evidence =
          entry.value.netEvidence.abs();

      if (retention <= minimumRetention &&
          evidence < 0.5) {
        toRemove.add(
          entry.key,
        );
      }
    }

    for (final key in toRemove) {
      _traces.remove(key);
    }

    return toRemove.length;
  }

  // ---------------------------------------------------------------------------
  // RECOMMENDATION SIGNAL
  // ---------------------------------------------------------------------------

  /// يحول الذاكرة إلى multiplier يستطيع الـRanker استخدامه.
  ///
  /// الذاكرة القوية + المرتفعة retention
  /// تعطي إشارة أكبر.
  double recommendationBoost(
    String key, {
    double base = 1.0,
    DateTime? now,
  }) {
    final trace =
        this.trace(key);

    if (trace == null) {
      return base;
    }

    final retention =
        retentionForTrace(
      trace,
      now: now,
    );

    if (retention <= 0.0) {
      return base;
    }

    final evidence =
        trace.netEvidence;

    final normalizedEvidence =
        evidence.clamp(
      -10.0,
      10.0,
    );

    final signal =
        normalizedEvidence / 10.0;

    final adjustment =
        signal * retention;

    return (base + adjustment)
        .clamp(
      0.05,
      2.0,
    );
  }

  /// هل هذه الذاكرة أصبحت جاهزة لإعادة الاستكشاف؟
  bool needsReExploration(
    String key, {
    DateTime? now,
    double threshold = 0.30,
  }) {
    return retention(
          key,
          now: now,
        ) <
        threshold.clamp(
          0.0,
          1.0,
        );
  }

  // ---------------------------------------------------------------------------
  // SERIALIZATION
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'base_half_life_ms':
          baseHalfLife.inMilliseconds,
      'minimum_retention':
          minimumRetention,
      'maximum_strength':
          maximumStrength,
      'review_boost':
          reviewBoost,
      'negative_penalty':
          negativePenalty,
      'traces': <String, dynamic>{
        for (final entry
            in _traces.entries)
          entry.key:
              entry.value.toJson(),
      },
    };
  }

  void restore(
    Map<String, dynamic> json,
  ) {
    _traces.clear();

    final raw =
        json['traces'];

    if (raw is! Map) {
      return;
    }

    raw.forEach(
      (key, value) {
        if (value is Map) {
          final trace =
              BeastMemoryTrace.fromJson(
            Map<String, dynamic>.from(
              value,
            ),
          );

          if (trace.key.isNotEmpty) {
            _traces[
                _normalize(
              trace.key,
            )] = trace;
          }
        }
      },
    );
  }

  void clear() {
    _traces.clear();
  }

  // ---------------------------------------------------------------------------
  // INTERNAL
  // ---------------------------------------------------------------------------

  static String _normalize(
    String value,
  ) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(
          RegExp(r'\s+'),
          '_',
        );
  }

  static double _safeDouble(
    Object? value, {
    double fallback = 0.0,
  }) {
    if (value is num) {
      final result =
          value.toDouble();

      return result.isFinite
          ? result
          : fallback;
    }

    return fallback;
  }

  static int _safeInt(
    Object? value,
  ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return 0;
  }
}
