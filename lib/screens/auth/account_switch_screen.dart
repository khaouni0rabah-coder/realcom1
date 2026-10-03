import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/beast/beast_tracker.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../widgets/liquid_background.dart';
import '../../widgets/liquid_glass_container.dart';
import '../../widgets/user_avatar.dart';

class AccountSwitchScreen extends StatefulWidget {
  const AccountSwitchScreen({
    super.key,
  });

  @override
  State<AccountSwitchScreen> createState() =>
      _AccountSwitchScreenState();
}

class _AccountSwitchScreenState
    extends State<AccountSwitchScreen> {
  final AuthSession _session =
      AuthSession.instance;

  void _switchAccount(String userId) {
    final previousId =
        _session.isAuthenticated
            ? _session.currentUser.id
            : null;

    final success =
        _session.login(userId);

    if (!success) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content:
              Text('تعذر تبديل الحساب.'),
        ),
      );
      return;
    }

    // 🐺 تتبع الدخول/التبديل.
    if (previousId == null) {
      BeastTracker.instance.loggedIn(userId);
    } else if (previousId != userId) {
      BeastTracker.instance.accountSwitched(
        fromUserId: previousId,
        toUserId: userId,
      );
    }

    if (!mounted) return;

    setState(() {});

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final currentId =
        _session.isAuthenticated
            ? _session.currentUser.id
            : null;

    final users = _session.users;

    return Scaffold(
      backgroundColor:
          AppColors.background,
      appBar: AppBar(
        title:
            const Text('تبديل الحساب'),
      ),
      body: Stack(
        children: [
          const LiquidBackground(),

          SafeArea(
            child: ListView.separated(
              padding:
                  const EdgeInsets.all(
                AppSpacing.x24,
              ),
              itemCount: users.length,
              separatorBuilder:
                  (_, __) =>
                      const SizedBox(
                height: AppSpacing.x12,
              ),
              itemBuilder:
                  (context, index) {
                final user =
                    users[index];

                final isCurrent =
                    user.id ==
                        currentId;

                return InkWell(
                  borderRadius:
                      BorderRadius.circular(
                    22,
                  ),
                  onTap: isCurrent
                      ? null
                      : () =>
                          _switchAccount(
                        user.id,
                      ),
                  child:
                      LiquidGlassContainer(
                    opacity:
                        isCurrent
                            ? 0.10
                            : 0.055,
                    padding:
                        const EdgeInsets
                            .all(
                      AppSpacing.x16,
                    ),
                    child: Row(
                      children: [
                        UserAvatar(
                          imageUrl:
                              user.avatarUrl,
                          size: 56,
                        ),

                        const SizedBox(
                          width: 14,
                        ),

                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                user.displayName,
                                style:
                                    AppTextStyles
                                        .titleMedium,
                              ),
                              const SizedBox(
                                height: 3,
                              ),
                              Text(
                                '@${user.username}',
                                style:
                                    AppTextStyles
                                        .username,
                              ),
                            ],
                          ),
                        ),

                        if (isCurrent)
                          const Icon(
                            Icons
                                .check_circle_rounded,
                            color:
                                AppColors.success,
                            size: 24,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
