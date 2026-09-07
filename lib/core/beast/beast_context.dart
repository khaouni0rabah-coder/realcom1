import 'dart:math' as math;

/// السياق السلوكي الحالي للمستخدم.
///
/// هذه ليست معلومات شخصية حساسة؛ هي حالة استخدام قصيرة المدى
/// تساعد Beast على فهم "ماذا يريد المستخدم الآن؟".
enum UserContext {
  morningRoutine,
  workMode,
  commute,
  eveningRelax,
  focusTime,
  socialMode,
  discoveryMode,
  unknown,
}

/// تقدير سلوكي خفيف للحالة الحالية.
///
/// مهم:
/// هذا ليس تشخيصًا نفسيًا أو طبيًا.
/// هو مجرد signal سلوكي للتخصيص.
enum UserMood {
  happy,
  sad,
  energetic,
  tired,
  curious,
  relaxed,
  focused,
  neutral,
}

/// سجل سلوكي مبسط تستعمله طبقة السياق فقط.
class BeastContextEvent {
  const BeastContextEvent({
    required this.type,
    required this.timestamp,
    this.tags = const <String>[],
    this.durationMs,
    this.value,
  });

  final String type;
  final DateTime timestamp;
  final List<String> tags;
  final int? durationMs;
  final double? value;
}

/// نتيجة تحليل السياق الحالية.
class BeastContextSnapshot {
  const BeastContextSnapshot({
    required this.context,
    required this.mood,
    required this.energy,
    required this.explorationRate,
    required this.timestamp,
    this.boosts = const <String, double>{},
  });

  final UserContext context;
  final UserMood mood;
  final double energy;
  final double explorationRate;
  final DateTime timestamp;
  final Map<String, double> boosts;

  BeastContextSnapshot copyWith({
    UserContext? context,
    UserMood? mood,
    double? energy,
    double? explorationRate,
    DateTime? timestamp,
    Map<String, double>? boosts,
  }) {
    return BeastContextSnapshot(
      context: context ?? this.context,
      mood: mood ?? this.mood,
      energy: energy ?? this.energy,
      explorationRate:
          explorationRate ?? this.explorationRate,
      timestamp: timestamp ?? this.timestamp,
      boosts: boosts ?? this.boosts,
    );
  }
}

/// محرك السياق الجديد للوحش.
///
/// لا يقرر المحتوى بنفسه.
/// مهمته إنتاج signals يستطيع Beast Ranker/Brain استعمالها.
class BeastContextEngine {
  BeastContextEngine({
    this.maxHistory = 100,
  });

  final int maxHistory;

  final List<BeastContextEvent> _history =
      <BeastContextEvent>[];

  double _energy = 0.5;

  BeastContextSnapshot _snapshot =
      BeastContextSnapshot(
    context: UserContext.unknown,
    mood: UserMood.neutral,
    energy: 0.5,
    explorationRate: 0.15,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
  );

  BeastContextSnapshot get snapshot =>
      _snapshot;

  List<BeastContextEvent> get history =>
      List.unmodifiable(_history);

  /// أضف سلوكًا جديدًا للتحليل.
  void observe(BeastContextEvent event) {
    _history.add(event);

    if (_history.length > maxHistory) {
      _history.removeRange(
        0,
        _history.length - maxHistory,
      );
    }

    _updateEnergy(event);

    _snapshot = analyze(
      now: event.timestamp,
    );
  }

  /// إعادة تحليل السياق دون إضافة event.
  BeastContextSnapshot analyze({
    DateTime? now,
  }) {
    final currentTime =
        now ?? DateTime.now();

    final context =
        ContextDetector.detect(
      _history,
      currentTime,
    );

    final mood =
        MoodDetector.detect(
      _history,
      _energy,
    );

    final exploration =
        MoodExplorer.getExplorationRate(
      mood,
      _history.length,
    );

    final boosts =
        ContextDetector.getContextBoost(
      context,
    );

    final moodBoosts =
        MoodDetector.getMoodBoost(
      mood,
    );

    final mergedBoosts =
        <String, double>{};

    for (final entry in boosts.entries) {
      mergedBoosts[entry.key] =
          (mergedBoosts[entry.key] ?? 1.0) *
              entry.value;
    }

    for (final entry
        in moodBoosts.entries) {
      mergedBoosts[entry.key] =
          (mergedBoosts[entry.key] ?? 1.0) *
              entry.value;
    }

    _snapshot =
        BeastContextSnapshot(
      context: context,
      mood: mood,
      energy: _energy,
      explorationRate: exploration,
      timestamp: currentTime,
      boosts: mergedBoosts,
    );

    return _snapshot;
  }

  void reset() {
    _history.clear();
    _energy = 0.5;

    _snapshot =
        BeastContextSnapshot(
      context: UserContext.unknown,
      mood: UserMood.neutral,
      energy: 0.5,
      explorationRate: 0.15,
      timestamp: DateTime.now(),
    );
  }

  void _updateEnergy(
    BeastContextEvent event,
  ) {
    double delta = 0.0;

    switch (event.type) {
      case 'open':
        delta += 0.08;
        break;

      case 'like':
      case 'love':
      case 'share':
        delta += 0.10;
        break;

      case 'save':
        delta += 0.05;
        break;

      case 'skip':
        delta -= 0.05;
        break;

      case 'hide':
      case 'not_interested':
        delta -= 0.10;
        break;

      case 'scroll':
        delta += 0.02;
        break;

      case 'duration':
        final ms =
            event.durationMs ?? 0;

        if (ms >= 30 * 1000) {
          delta -= 0.04;
        } else if (ms <= 5 * 1000) {
          delta += 0.04;
        }
        break;
    }

    _energy =
        (_energy + delta).clamp(
      0.0,
      1.0,
    );
  }
}

/// اكتشاف السياق الحالي.
class ContextDetector {
  static UserContext detect(
    List<BeastContextEvent> events,
    DateTime now,
  ) {
    final hour = now.hour;
    final isWeekend =
        now.weekday >= DateTime.saturday;

    final recent =
        events.reversed.take(20);

    final tags =
        <String>{};

    for (final event in recent) {
      tags.addAll(event.tags);
    }

    if (hour >= 5 && hour < 9) {
      return UserContext.morningRoutine;
    }

    if (hour >= 9 &&
        hour < 17 &&
        !isWeekend) {
      if (_containsAny(
        tags,
        const <String>[
          'educational',
          'learning',
          'deep',
          'tutorial',
        ],
      )) {
        return UserContext.focusTime;
      }

      return UserContext.workMode;
    }

    if (hour >= 17 &&
        hour < 19) {
      return UserContext.commute;
    }

    if (hour >= 19 &&
        hour < 23) {
      if (_containsAny(
        tags,
        const <String>[
          'social',
          'friends',
          'community',
        ],
      )) {
        return UserContext.socialMode;
      }

      if (_containsAny(
        tags,
        const <String>[
          'discovery',
          'explore',
          'new',
        ],
      )) {
        return UserContext.discoveryMode;
      }

      return UserContext.eveningRelax;
    }

    return UserContext.eveningRelax;
  }

  static Map<String, double> getContextBoost(
    UserContext context,
  ) {
    switch (context) {
      case UserContext.morningRoutine:
        return <String, double>{
          'news': 1.5,
          'podcast': 1.3,
          'fitness': 1.2,
        };

      case UserContext.workMode:
        return <String, double>{
          'productivity': 1.5,
          'educational': 1.4,
          'technology': 1.3,
        };

      case UserContext.commute:
        return <String, double>{
          'short': 1.5,
          'music': 1.4,
          'podcast': 1.3,
        };

      case UserContext.eveningRelax:
        return <String, double>{
          'entertainment': 1.5,
          'movie': 1.4,
          'series': 1.3,
        };

      case UserContext.focusTime:
        return <String, double>{
          'deep': 1.5,
          'educational': 1.4,
          'long_form': 1.3,
        };

      case UserContext.socialMode:
        return <String, double>{
          'social': 1.5,
          'friends': 1.4,
          'trending': 1.3,
        };

      case UserContext.discoveryMode:
        return <String, double>{
          'discovery': 1.5,
          'novel': 1.4,
          'exploration': 1.3,
        };

      case UserContext.unknown:
        return const <String, double>{};
    }
  }

  static bool _containsAny(
    Set<String> source,
    List<String> values,
  ) {
    for (final value in values) {
      if (source.contains(value)) {
        return true;
      }
    }

    return false;
  }
}

/// تقدير الحالة السلوكية الحالية.
///
/// لا ينبغي تفسيره كقياس طبي أو نفسي حقيقي.
class MoodDetector {
  static UserMood detect(
    List<BeastContextEvent> events,
    double energy,
  ) {
    final recent =
        events.reversed.take(30).toList();

    if (recent.isEmpty) {
      return UserMood.neutral;
    }

    var likes = 0;
    var skips = 0;
    var longEngagement = 0;
    var fastEngagement = 0;
    var educational = 0;
    var comedy = 0;
    var music = 0;
    var focusedActions = 0;

    for (final event in recent) {
      switch (event.type) {
        case 'like':
        case 'love':
          likes++;
          break;

        case 'skip':
        case 'not_interested':
          skips++;
          break;

        case 'duration':
          final ms =
              event.durationMs ?? 0;

          if (ms >= 30 * 1000) {
            longEngagement++;
          }

          if (ms <= 5 * 1000) {
            fastEngagement++;
          }
          break;
      }

      for (final tag in event.tags) {
        final normalized =
            tag.toLowerCase();

        if (normalized.contains(
          'educational',
        )) {
          educational++;
        }

        if (normalized.contains(
          'comedy',
        )) {
          comedy++;
        }

        if (normalized.contains(
          'music',
        )) {
          music++;
        }

        if (normalized.contains(
          'focus',
        )) {
          focusedActions++;
        }
      }
    }

    final total =
        likes + skips;

    final positiveRate =
        total == 0
            ? 0.5
            : likes / total;

    if (energy >= 0.75 &&
        fastEngagement >= longEngagement) {
      return UserMood.energetic;
    }

    if (energy <= 0.25 &&
        skips >= likes) {
      return UserMood.tired;
    }

    if (comedy > 0 &&
        positiveRate >= 0.65) {
      return UserMood.happy;
    }

    if (educational >= 3 &&
        longEngagement >= 2) {
      return UserMood.curious;
    }

    if (focusedActions >= 2 &&
        longEngagement >= 2) {
      return UserMood.focused;
    }

    if (music >= 2 &&
        energy < 0.60) {
      return UserMood.relaxed;
    }

    if (positiveRate <= 0.25 &&
        skips >= 3) {
      return UserMood.sad;
    }

    return UserMood.neutral;
  }

  static Map<String, double> getMoodBoost(
    UserMood mood,
  ) {
    switch (mood) {
      case UserMood.happy:
        return <String, double>{
          'comedy': 1.5,
          'fun': 1.4,
          'positive': 1.3,
        };

      case UserMood.sad:
        return <String, double>{
          'inspirational': 1.4,
          'uplifting': 1.3,
          'music': 1.2,
        };

      case UserMood.energetic:
        return <String, double>{
          'action': 1.4,
          'sports': 1.3,
          'music': 1.3,
        };

      case UserMood.tired:
        return <String, double>{
          'relax': 1.5,
          'calm': 1.4,
          'ambient': 1.3,
        };

      case UserMood.curious:
        return <String, double>{
          'educational': 1.5,
          'science': 1.4,
          'documentary': 1.3,
        };

      case UserMood.relaxed:
        return <String, double>{
          'nature': 1.4,
          'ambient': 1.3,
          'calm': 1.2,
        };

      case UserMood.focused:
        return <String, double>{
          'deep': 1.5,
          'educational': 1.4,
          'long_form': 1.3,
        };

      case UserMood.neutral:
        return const <String, double>{};
    }
  }
}

/// يحدد معدّل الاستكشاف (exploration rate) بناءً على الحالة المزاجية
/// وحجم الخبرة السلوكية المتراكمة لدى المستخدم.
///
/// الفكرة: كل ما زاد عدد الأحداث المسجّلة (historyLength)، كل ما قلّت
/// الحاجة للاستكشاف العشوائي لأن النظام صار "يعرف" المستخدم أكثر
/// (exploitation بدل exploration). بعض الحالات المزاجية (مثل الفضول
/// والطاقة) تزيد الرغبة الطبيعية بتجربة محتوى جديد، بينما حالات أخرى
/// (مثل التعب أو التركيز العميق) تفضّل محتوى مألوفًا وموثوقًا.
class MoodExplorer {
  /// الحد الأدنى/الأقصى لمعدل الاستكشاف حتى لا يصل لصفر أو يتجاوز 1.
  static const double _minRate = 0.05;
  static const double _maxRate = 0.55;

  static const Map<UserMood, double> _moodMultiplier = {
    UserMood.curious: 1.4,
    UserMood.energetic: 1.2,
    UserMood.happy: 1.1,
    UserMood.neutral: 1.0,
    UserMood.relaxed: 0.9,
    UserMood.sad: 0.85,
    UserMood.focused: 0.6,
    UserMood.tired: 0.5,
  };

  /// [mood] الحالة المزاجية الحالية.
  /// [historyLength] عدد الأحداث السلوكية المسجّلة حتى الآن.
  static double getExplorationRate(
    UserMood mood,
    int historyLength,
  ) {
    // خط أساس يتناقص كلما زادت الخبرة (decay)، يبدأ من ~0.35 عند
    // عدم وجود أي تاريخ وينخفض تدريجيًا مع تراكم الأحداث.
    final baseline =
        0.35 * math.exp(-historyLength / 200.0);

    final multiplier = _moodMultiplier[mood] ?? 1.0;

    final rate = baseline * multiplier;

    return rate.clamp(_minRate, _maxRate);
  }
}
