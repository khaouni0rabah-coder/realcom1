// lib/core/beast/beast_user_session.dart

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import 'beast.dart';
import 'beast_server_config.dart';

/// يربط هوية المستخدم بدورة حياة 🐺 Beast.
///
/// المسؤوليات:
/// - مراقبة المستخدم الحالي في AuthSession.
/// - تهيئة Beast للمستخدم المسجل (مع إعدادات الخادم).
/// - تبديل المستخدم بأمان عبر BeastUltimate.switchUser.
/// - إنهاء الجلسة عند تسجيل الخروج.
/// - منع التهيئة المكررة أو خلط ذاكرة مستخدم بآخر.
///
/// الخصوصية:
/// - لا تُمنح الموافقة تلقائيًا هنا أبدًا.
/// - الموافقة تُقرأ من التخزين الدائم (setConsent يحفظها)،
///   أو تُطلب من المستخدم عبر واجهة الخصوصية في الإعدادات.
class BeastUserSession extends ChangeNotifier {
  BeastUserSession._();

  static final BeastUserSession instance =
      BeastUserSession._();

  final AuthSession _auth =
      AuthSession.instance;

  final BeastUltimate _beast =
      BeastUltimate();

  bool _attached = false;
  bool _syncing = false;

  String? _boundUserId;

  bool get attached => _attached;

  String? get boundUserId => _boundUserId;

  BeastUltimate get beast => _beast;

  /// يبدأ مراقبة AuthSession.
  ///
  /// يجب استدعاؤها مرة واحدة أثناء bootstrap.
  void attach() {
    if (_attached) {
      return;
    }

    _attached = true;

    _auth.addListener(
      _onAuthChanged,
    );

    unawaited(
      reconcile(),
    );
  }

  /// يوقف مراقبة AuthSession.
  Future<void> detach() async {
    if (!_attached) {
      return;
    }

    _auth.removeListener(
      _onAuthChanged,
    );

    _attached = false;

    await logout();

    notifyListeners();
  }

  void _onAuthChanged() {
    unawaited(
      reconcile(),
    );
  }

  /// يجعل Beast متوافقًا مع المستخدم الحالي.
  Future<void> reconcile() async {
    if (_syncing) {
      return;
    }

    _syncing = true;

    try {
      if (!_auth.isAuthenticated) {
        await logout();
        return;
      }

      final userId =
          _auth.currentUser.id.trim();

      if (userId.isEmpty) {
        await logout();
        return;
      }

      // نفس المستخدم: لا حاجة لتهيئة جديدة.
      if (_boundUserId == userId &&
          _beast.ready) {
        return;
      }

      await login(userId);
    } catch (error, stackTrace) {
      debugPrint(
        'BeastUserSession.reconcile failed: '
        '$error\n$stackTrace',
      );
    } finally {
      _syncing = false;
    }
  }

  /// يربط Beast بالمستخدم.
  ///
  /// BeastUltimate.init يتعامل داخليًا مع حالتي
  /// "غير مهيأ" و"مستخدم مختلف" (عبر switchUser)،
  /// لذلك لا نحتاج منطق تبديل هنا.
  Future<void> login(
    String userId,
  ) async {
    final normalized =
        userId.trim();

    if (normalized.isEmpty) {
      return;
    }

    if (_boundUserId == normalized &&
        _beast.ready) {
      return;
    }

    try {
      await _beast.init(
        userId: normalized,
        config: BeastServerConfig.buildConfig(),
      );

      _boundUserId = normalized;

      // ملاحظة خصوصية:
      // لا نستدعي setConsent(granted) تلقائيًا.
      // الموافقة تُحمّل من التخزين الدائم إن وُجدت،
      // وإلا تبقى notDetermined حتى يقرر المستخدم
      // من شاشة الخصوصية/الإعدادات.
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint(
        'BeastUserSession.login failed: '
        '$error\n$stackTrace',
      );
    }
  }

  /// يمنح موافقة التتبع — تُستدعى من واجهة المستخدم فقط.
  Future<void> grantConsent() async {
    if (!_beast.ready) {
      return;
    }

    try {
      await _beast.setConsent(BeastConsent.granted);
      notifyListeners();
    } catch (error) {
      debugPrint(
        'BeastUserSession.grantConsent failed: $error',
      );
    }
  }

  /// يرفض موافقة التتبع ويمسح بيانات السلوك المحلية.
  Future<void> denyConsent() async {
    if (!_beast.ready) {
      return;
    }

    try {
      await _beast.setConsent(BeastConsent.denied);
      notifyListeners();
    } catch (error) {
      debugPrint(
        'BeastUserSession.denyConsent failed: $error',
      );
    }
  }

  /// تسجيل خروج منطقي من طبقة المستخدم.
  ///
  /// لا يستدعي dispose() هنا، لأن BeastUltimate يحتوي
  /// على موارد طويلة العمر وسياسة lifecycle خاصة به.
  Future<void> logout() async {
    if (_boundUserId == null) {
      return;
    }

    try {
      if (_beast.ready &&
          _beast.consent ==
              BeastConsent.granted) {
        await _beast.onBackground();
      }
    } catch (error, stackTrace) {
      debugPrint(
        'BeastUserSession.logout background failed: '
        '$error\n$stackTrace',
      );
    }

    _boundUserId = null;

    notifyListeners();
  }
}
