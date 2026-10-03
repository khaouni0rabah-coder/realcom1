// lib/core/beast/beast_server_config.dart

import 'beast.dart';

/// إعدادات اتصال الوحش بالخادم (Big Beast).
///
/// غيّر [serverUrl] إلى عنوان خادمك الفعلي.
/// الخادم يجب أن يوفّر نقاط النهاية:
/// - POST /v2/beast/events/batch     (استقبال دفعات الأحداث)
/// - POST /v2/beast/experience/batch (استقبال خبرات التعلم)
/// - GET  /v2/beast/model            (تحديثات النموذج)
/// - POST /v2/beast/recommend        (توصيات الخادم)
///
/// إذا بقي العنوان فارغًا أو تعذر الوصول للخادم،
/// يستمر الوحش بالعمل محليًا بالكامل بدون أي عطل.
class BeastServerConfig {
  BeastServerConfig._();

  /// عنوان الخادم — ضع عنوانك هنا.
  static const String serverUrl =
      'https://your-app.up.railway.app';

  /// هل الاتصال بالخادم مفعّل؟
  static bool get enabled => serverUrl.trim().isNotEmpty;

  /// يبني إعدادات Beast الافتراضية للتطبيق.
  static BeastConfig buildConfig() {
    return const BeastConfig(
      serverUrl: serverUrl,
      flushInterval: Duration(seconds: 12),
      batchSize: 100,
      privacy: BeastPrivacy.standard,
      autoRoutes: true,
      autoLifecycle: true,
      autoNetwork: true,
      autoPerformance: true,
      autoCrashTracking: true,
      enableGzip: true,
    );
  }
}
