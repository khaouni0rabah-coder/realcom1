// lib/core/beast/beast_tracker.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'beast.dart';

/// الواجهة الموحدة والآمنة لتتبع كل شيء في التطبيق.
///
/// 🐺 القاعدة الذهبية: التتبع يجب ألّا يكسر التطبيق أبدًا.
///
/// - كل دوال هذا الصنف متزامنة الشكل (void) ولا ترمي استثناءات.
/// - كل حدث يُرسل في الخلفية (fire-and-forget) مع ابتلاع الأخطاء.
/// - إذا كان Beast غير جاهز أو بلا موافقة: يُتجاهل الحدث بهدوء.
/// - الشاشات لا تتحدث مع BeastUltimate مباشرة؛ تتحدث مع هذا الصنف فقط.
///
/// يغطي:
/// - الشاشات (يدويًا أو تلقائيًا عبر [navigatorObserver]).
/// - النقرات على الأزرار.
/// - ظهور المحتوى / فتحه / مدة بقائه / تخطيه.
/// - التفاعلات: إعجاب، حفظ، مشاركة، غير مهتم.
/// - التصويت، التعليقات، الردود.
/// - المتابعة، البحث، فتح الإشعارات.
/// - تسجيل الدخول / الخروج / تبديل الحساب.
class BeastTracker {
  BeastTracker._();

  static final BeastTracker instance = BeastTracker._();

  BeastUltimate get _beast => BeastUltimate();

  /// مراقب التنقل التلقائي — أضفه إلى MaterialApp.navigatorObservers.
  NavigatorObserver get navigatorObserver =>
      _beast.navigatorObserver;

  /// هل الوحش مستعد لاستقبال الأحداث الآن؟
  bool get isActive =>
      _beast.ready &&
      _beast.consent == BeastConsent.granted;

  /// منفذ تنفيذ آمن لأي حدث.
  ///
  /// لا يفعل شيئًا إذا كان الوحش غير جاهز،
  /// ويبتلع أي خطأ حتى لا يتأثر مسار المستخدم.
  void _track(
    String label,
    Future<void> Function(BeastUltimate beast) action,
  ) {
    if (!_beast.ready) {
      return;
    }

    try {
      unawaited(
        action(_beast).catchError(
          (Object error, StackTrace stackTrace) {
            debugPrint(
              'BeastTracker.$label failed: $error',
            );
          },
        ),
      );
    } catch (error) {
      // خطأ متزامن (نادر) — لا نسمح له بالصعود أبدًا.
      debugPrint(
        'BeastTracker.$label sync failure: $error',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // الشاشات
  // ---------------------------------------------------------------------------

  /// شاشة ظهرت للمستخدم (يُستدعى تلقائيًا عبر navigatorObserver،
  /// ويمكن استدعاؤه يدويًا للشاشات داخل Tabs أو BottomSheets).
  void screenViewed(String screenName) {
    _track(
      'screenViewed',
      (beast) => beast.screen(screenName),
    );
  }

  // ---------------------------------------------------------------------------
  // النقرات
  // ---------------------------------------------------------------------------

  /// نقرة على زر أو عنصر واجهة.
  void tap(
    String name, {
    Map<String, dynamic>? extra,
  }) {
    _track(
      'tap',
      (beast) => beast.button(name, extra: extra),
    );
  }

  // ---------------------------------------------------------------------------
  // دورة المحتوى: ظهور → فتح → مدة → تخطي
  // ---------------------------------------------------------------------------

  void impression({
    required String itemId,
    List<String> tags = const <String>[],
    String? category,
    String? creatorId,
    int position = 0,
    String source = 'unknown',
  }) {
    _track(
      'impression',
      (beast) => beast.impression(
        itemId: itemId,
        tags: tags,
        category: category,
        creatorId: creatorId,
        position: position,
        source: source,
      ),
    );
  }

  void opened({
    required String itemId,
    List<String> tags = const <String>[],
    String? category,
    String? creatorId,
    int position = 0,
    String source = 'unknown',
  }) {
    _track(
      'opened',
      (beast) => beast.openContent(
        itemId: itemId,
        tags: tags,
        category: category,
        creatorId: creatorId,
        position: position,
        source: source,
      ),
    );
  }

  /// مدة بقاء المستخدم على محتوى (بالمللي ثانية).
  void duration({
    required String itemId,
    required int durationMs,
    List<String> tags = const <String>[],
    String? category,
    String? creatorId,
  }) {
    if (durationMs <= 0) {
      return;
    }

    _track(
      'duration',
      (beast) => beast.duration(
        itemId: itemId,
        durationMs: durationMs,
        tags: tags,
        category: category,
        creatorId: creatorId,
      ),
    );
  }

  /// سحب/تخطي البطاقة بدون تفاعل.
  void swipedAway({
    required String itemId,
    List<String> tags = const <String>[],
  }) {
    _track(
      'swipedAway',
      (beast) => beast.skip(itemId, tags: tags),
    );
  }

  void hidden({required String itemId, String? reason}) {
    _track(
      'hidden',
      (beast) => beast.hide(itemId, reason: reason),
    );
  }

  // ---------------------------------------------------------------------------
  // التفاعلات الدلالية
  // ---------------------------------------------------------------------------

  void _reaction({
    required String reaction,
    required String itemId,
    List<String> tags,
    String? category,
    String? creatorId,
  }) {
    _track(
      'reaction:$reaction',
      (beast) => beast.reaction(
        itemId: itemId,
        reaction: reaction,
        tags: tags,
        category: category,
        creatorId: creatorId,
      ),
    );
  }

  void liked({
    required String itemId,
    List<String> tags = const <String>[],
    String? category,
    String? creatorId,
  }) {
    _reaction(
      reaction: 'like',
      itemId: itemId,
      tags: tags,
      category: category,
      creatorId: creatorId,
    );
  }

  void unliked({
    required String itemId,
    List<String> tags = const <String>[],
    String? category,
    String? creatorId,
  }) {
    _reaction(
      reaction: 'unlike',
      itemId: itemId,
      tags: tags,
      category: category,
      creatorId: creatorId,
    );
  }

  void saved({
    required String itemId,
    List<String> tags = const <String>[],
    String? category,
    String? creatorId,
  }) {
    _reaction(
      reaction: 'save',
      itemId: itemId,
      tags: tags,
      category: category,
      creatorId: creatorId,
    );
  }

  void shared({
    required String itemId,
    List<String> tags = const <String>[],
    String? category,
    String? creatorId,
  }) {
    _reaction(
      reaction: 'share',
      itemId: itemId,
      tags: tags,
      category: category,
      creatorId: creatorId,
    );
  }

  void notInterested({
    required String itemId,
    List<String> tags = const <String>[],
    String? category,
    String? creatorId,
  }) {
    _reaction(
      reaction: 'not_interested',
      itemId: itemId,
      tags: tags,
      category: category,
      creatorId: creatorId,
    );
  }

  // ---------------------------------------------------------------------------
  // التصويت والتعليقات والردود
  // ---------------------------------------------------------------------------

  void voted({
    required String itemId,
    String? option,
    String? category,
    String? creatorId,
  }) {
    _track(
      'voted',
      (beast) => beast.vote(
        itemId,
        option: option,
        category: category,
        creatorId: creatorId,
      ),
    );
  }

  void commented({
    required String itemId,
    required String text,
    String? category,
    String? creatorId,
  }) {
    _track(
      'commented',
      (beast) => beast.comment(
        itemId: itemId,
        text: text,
        category: category,
        creatorId: creatorId,
      ),
    );
  }

  void replied({
    required String itemId,
    String? category,
    String? creatorId,
    String? parentCommentId,
  }) {
    _track(
      'replied',
      (beast) => beast.reply(
        itemId,
        category: category,
        creatorId: creatorId,
        parentCommentId: parentCommentId,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // الاجتماعي والبحث والإشعارات
  // ---------------------------------------------------------------------------

  void followed({required String userId, String? category}) {
    _track(
      'followed',
      (beast) => beast.follow(userId, category: category),
    );
  }

  void unfollowed({required String userId}) {
    _track(
      'unfollowed',
      (beast) => beast.button(
        'unfollow',
        extra: <String, dynamic>{'target_user': userId},
      ),
    );
  }

  void searched({required String query, int resultCount = 0}) {
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      return;
    }

    _track(
      'searched',
      (beast) => beast.search(trimmed, resultCount: resultCount),
    );
  }

  void notificationOpened(String notificationId) {
    _track(
      'notificationOpened',
      (beast) => beast.notificationOpened(notificationId),
    );
  }

  // ---------------------------------------------------------------------------
  // الجلسة والحساب
  // ---------------------------------------------------------------------------

  /// دخول مستخدم — يرسل حدثًا دلاليًا، بينما ربط الهوية نفسه
  /// مسؤولية BeastUserSession.
  void loggedIn(String userId) {
    _track(
      'loggedIn',
      (beast) => beast.button(
        'auth_login',
        extra: <String, dynamic>{'user_id': userId},
      ),
    );
  }

  void loggedOut(String userId) {
    _track(
      'loggedOut',
      (beast) => beast.button(
        'auth_logout',
        extra: <String, dynamic>{'user_id': userId},
      ),
    );
  }

  void accountSwitched({
    required String fromUserId,
    required String toUserId,
  }) {
    _track(
      'accountSwitched',
      (beast) => beast.button(
        'auth_switch',
        extra: <String, dynamic>{
          'from_user_id': fromUserId,
          'to_user_id': toUserId,
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // التحكم في التوصيات (واجهة المستخدم)
  // ---------------------------------------------------------------------------

  void moreLikeThis({
    required String itemId,
    List<String> tags = const <String>[],
  }) {
    _track(
      'moreLikeThis',
      (beast) => beast.moreLikeThis(itemId, tags: tags),
    );
  }

  void lessLikeThis({
    required String itemId,
    List<String> tags = const <String>[],
  }) {
    _track(
      'lessLikeThis',
      (beast) => beast.lessLikeThis(itemId, tags: tags),
    );
  }

  void recommendationFeedback({
    required String itemId,
    required String feedback,
  }) {
    _track(
      'recommendationFeedback',
      (beast) => beast.recommendationFeedback(
        itemId,
        feedback: feedback,
      ),
    );
  }
}
