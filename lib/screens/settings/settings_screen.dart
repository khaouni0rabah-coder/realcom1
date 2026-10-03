import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/beast/beast.dart';
import '../../core/beast/beast_tracker.dart';
import '../../core/beast/beast_user_session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../auth/account_switch_screen.dart';
import '../notifications/notifications_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
  });

  Future<void> _logout(
    BuildContext context,
  ) async {
    final shouldLogout =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
              const Text('تسجيل الخروج'),
          content:
              const Text(
            'هل تريد تسجيل الخروج من هذا الحساب؟',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                false,
              ),
              child:
                  const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                true,
              ),
              child:
                  const Text('خروج'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) {
      return;
    }

    // 🐺 تتبع الخروج قبل قطع الجلسة.
    final userId =
        AuthSession.instance.currentUser.id;

    BeastTracker.instance.loggedOut(userId);

    AuthSession.instance.logout();

    if (!context.mounted) {
      return;
    }

    // Remove settings from the navigation
    // stack. AuthGate in main.dart will now
    // display the account screen.
    Navigator.of(context)
        .popUntil(
      (route) => route.isFirst,
    );
  }

  Future<void> _switchAccount(
    BuildContext context,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const AccountSwitchScreen(),
      ),
    );
  }

  Widget _sectionTitle(
    String title,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        right: 4,
        bottom: 8,
      ),
      child: Text(
        title,
        style:
            AppTextStyles.caption
                .copyWith(
          color:
              AppColors.textSecondary,
          fontWeight:
              FontWeight.w600,
        ),
      ),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(
        AppRadius.button,
      ),
      child: Container(
        constraints:
            const BoxConstraints(
          minHeight: 60,
        ),
        padding:
            const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        decoration:
            BoxDecoration(
          color:
              AppColors.surface,
          borderRadius:
              BorderRadius.circular(
            AppRadius.button,
          ),
          border:
              Border.all(
            color: AppColors
                .divider
                .withOpacity(
              0.60,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration:
                  BoxDecoration(
                shape:
                    BoxShape.circle,
                color:
                    (iconColor ??
                            AppColors
                                .textPrimary)
                        .withOpacity(
                  0.10,
                ),
              ),
              child: Icon(
                icon,
                size: 21,
                color:
                    iconColor ??
                        AppColors
                            .textPrimary,
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    title,
                    style:
                        AppTextStyles
                            .bodyLarge,
                  ),
                  if (subtitle !=
                      null) ...[
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      subtitle,
                      style:
                          AppTextStyles
                              .caption,
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                const Icon(
                  Icons
                      .chevron_left_rounded,
                  color:
                      AppColors
                          .textSecondary,
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final user =
        AuthSession.instance
            .currentUser;

    return Scaffold(
      backgroundColor:
          AppColors.background,
      appBar: AppBar(
        title:
            const Text('الإعدادات'),
      ),
      body: SafeArea(
        child:
            ListView(
          padding:
              const EdgeInsets.fromLTRB(
            AppSpacing.x16,
            AppSpacing.x12,
            AppSpacing.x16,
            AppSpacing.x24,
          ),
          children: [
            _sectionTitle(
              'الحساب',
            ),

            _settingTile(
              icon:
                  Icons.person_outline_rounded,
              title:
                  'الحساب الحالي',
              subtitle:
                  '@${user.username}',
            ),

            const SizedBox(
              height: AppSpacing.x8,
            ),

            _settingTile(
              icon:
                  Icons.swap_horiz_rounded,
              title:
                  'تبديل الحساب',
              subtitle:
                  'تجريبي حاليًا',
              onTap: () =>
                  _switchAccount(
                context,
              ),
            ),

            const SizedBox(
              height: AppSpacing.x24,
            ),

            _sectionTitle(
              'التطبيق',
            ),

            _settingTile(
              icon:
                  Icons.notifications_outlined,
              title:
                  'الإشعارات',
              subtitle:
                  'عرض الإشعارات والتحديثات',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const NotificationsScreen(),
                  ),
                );
              },
            ),

            const SizedBox(
              height: AppSpacing.x8,
            ),

            _settingTile(
              icon:
                  Icons.dark_mode_outlined,
              title:
                  'المظهر',
              subtitle:
                  'سنضيف System / Dark / Light هنا',
              onTap: () {},
            ),

            const SizedBox(
              height: AppSpacing.x24,
            ),

            _sectionTitle(
              'الخصوصية',
            ),

            const BeastPrivacyTile(),

            const SizedBox(
              height: AppSpacing.x24,
            ),

            _sectionTitle(
              'الحساب والأمان',
            ),

            _settingTile(
              icon:
                  Icons.logout_rounded,
              title:
                  'تسجيل الخروج',
              subtitle:
                  'الخروج من الحساب الحالي',
              iconColor:
                  AppColors.error,
              onTap: () =>
                  _logout(context),
              trailing:
                  const Icon(
                Icons
                    .chevron_left_rounded,
                color:
                    AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 🐺 بطاقة التحكم بخصوصية الوحش (التوصيات والتعلم).
///
/// تعرض حالة الموافقة الحالية وتسمح للمستخدم
/// بالمنح أو الرفض (مع مسح بيانات السلوك المحلية).
class BeastPrivacyTile extends StatefulWidget {
  const BeastPrivacyTile({super.key});

  @override
  State<BeastPrivacyTile> createState() =>
      _BeastPrivacyTileState();
}

class _BeastPrivacyTileState
    extends State<BeastPrivacyTile> {
  final _session = BeastUserSession.instance;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onChanged);
  }

  @override
  void dispose() {
    _session.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final beast = _session.beast;

    final String statusText;
    final Color statusColor;

    switch (beast.consent) {
      case BeastConsent.granted:
        statusText =
            'التخصيص مفعّل — الوحش يتعلم من نشاطك';
        statusColor = AppColors.success;
      case BeastConsent.denied:
        statusText =
            'التخصيص متوقف — لا يتم جمع أي سلوك';
        statusColor = AppColors.error;
      case BeastConsent.notDetermined:
        statusText =
            'لم تقرر بعد — التخصيص متوقف حاليًا';
        statusColor = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.all(
        AppSpacing.x16,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            BorderRadius.circular(
          AppRadius.card,
        ),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons
                    .psychology_alt_outlined,
                color: statusColor,
              ),
              const SizedBox(
                width: AppSpacing.x8,
              ),
              Expanded(
                child: Text(
                  'التوصيات الذكية',
                  style:
                      AppTextStyles.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: AppSpacing.x8,
          ),
          Text(
            statusText,
            style:
                AppTextStyles.caption.copyWith(
              color: statusColor,
            ),
          ),
          const SizedBox(
            height: AppSpacing.x12,
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      _session.denyConsent(),
                  child: const Text('إيقاف'),
                ),
              ),
              const SizedBox(
                width: AppSpacing.x8,
              ),
              Expanded(
                child: ElevatedButton(
                  onPressed: () =>
                      _session.grantConsent(),
                  child:
                      const Text('تفعيل'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
