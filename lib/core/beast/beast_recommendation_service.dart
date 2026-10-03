// lib/core/beast/beast_recommendation_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'beast.dart';

/// خدمة التوصيات عالية المستوى — "الوحش يرتّب المحتوى".
///
/// تُحوّل عناصر التطبيق (أسئلة، بطاقات خلاصة، حزم) إلى
/// [BeastCandidate]، وتطلب من Beast ترتيبها، ثم تعيدها
/// مرتبة من الأنسب للمستخدم إلى الأقل.
///
/// الاستقرار أولًا:
/// - إذا كان Beast غير جاهز أو الخادم لا يرد،
///   يُعاد الترتيب الأصلي بدون أي تغيير.
/// - لا ترمي استثناءات أبدًا.
class BeastRecommendationService {
  BeastRecommendationService._();

  static final BeastRecommendationService instance =
      BeastRecommendationService._();

  BeastUltimate get _beast => BeastUltimate();

  /// يرتّب قائمة عناصر حسب توصية الوحش.
  ///
  /// [items]        : العناصر الأصلية بترتيبها الحالي.
  /// [idOf]         : تستخرج معرّف المحتوى من العنصر.
  /// [tagsOf]       : وسوم/هاشتاقات العنصر (اختياري).
  /// [categoryOf]   : فئة العنصر (اختياري).
  /// [creatorIdOf]  : معرّف الناشر (اختياري).
  /// [context]      : اسم السياق، مثل 'online_feed'.
  /// [limit]        : أقصى عدد يُعاد (0 = الكل).
  ///
  /// تعيد قائمة مرتبة من نفس النوع [T].
  /// عند أي فشل تعيد [items] كما هي.
  Future<List<T>> rank<T>({
    required List<T> items,
    required String Function(T item) idOf,
    List<String> Function(T item)? tagsOf,
    String? Function(T item)? categoryOf,
    String? Function(T item)? creatorIdOf,
    String context = 'feed',
    int limit = 0,
  }) async {
    if (items.length < 2) {
      return items;
    }

    if (!_beast.ready ||
        _beast.consent != BeastConsent.granted) {
      return items;
    }

    try {
      final candidates = <BeastCandidate>[
        for (final item in items)
          BeastCandidate(
            itemId: idOf(item),
            tags: tagsOf?.call(item) ?? const <String>[],
            category: categoryOf?.call(item),
            creatorId: creatorIdOf?.call(item),
          ),
      ];

      final recommendations = await _beast.recommend(
        candidates,
        context: context,
        limit: limit > 0 ? limit : items.length,
      );

      if (recommendations.isEmpty) {
        return items;
      }

      // خريطة: معرّف → ترتيبه حسب نقاط الوحش.
      final scoreById = <String, double>{
        for (final rec in recommendations)
          rec.itemId: rec.score,
      };

      final ranked = List<T>.of(items);

      ranked.sort((a, b) {
        final scoreA = scoreById[idOf(a)] ?? 0;
        final scoreB = scoreById[idOf(b)] ?? 0;
        return scoreB.compareTo(scoreA);
      });

      if (limit > 0 && ranked.length > limit) {
        return ranked.sublist(0, limit);
      }

      return ranked;
    } catch (error) {
      debugPrint(
        'BeastRecommendationService.rank failed: $error',
      );
      return items;
    }
  }

  /// نسخة متزامنة آمنة: تُشغّل الترتيب في الخلفية وتستدعي
  /// [onRanked] عند الانتهاء فقط إذا كان [isAlive] لا يزال true.
  ///
  /// مثالية للاستخدام داخل initState/الشاشات:
  /// ```dart
  /// BeastRecommendationService.instance.rankInBackground(
  ///   items: _cards,
  ///   idOf: (c) => c.id,
  ///   context: 'online_feed',
  ///   isAlive: () => mounted,
  ///   onRanked: (ranked) => setState(() => _cards = ranked),
  /// );
  /// ```
  void rankInBackground<T>({
    required List<T> items,
    required String Function(T item) idOf,
    List<String> Function(T item)? tagsOf,
    String? Function(T item)? categoryOf,
    String? Function(T item)? creatorIdOf,
    String context = 'feed',
    int limit = 0,
    required bool Function() isAlive,
    required void Function(List<T> ranked) onRanked,
  }) {
    unawaited(
      rank<T>(
        items: items,
        idOf: idOf,
        tagsOf: tagsOf,
        categoryOf: categoryOf,
        creatorIdOf: creatorIdOf,
        context: context,
        limit: limit,
      ).then((ranked) {
        if (isAlive()) {
          onRanked(ranked);
        }
      }).catchError((Object error) {
        debugPrint(
          'BeastRecommendationService.rankInBackground '
          'failed: $error',
        );
      }),
    );
  }
}
