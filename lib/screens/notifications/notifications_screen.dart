import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/user_directory.dart';
import '../../core/beast/beast_tracker.dart';
import '../../core/notifications/notification_store.dart';
import '../../core/online/question_pack_store.dart';
import '../../core/online/question_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/notification.dart';
import '../../models/publisher.dart';
import '../../widgets/liquid_background.dart';
import '../../widgets/liquid_glass_container.dart';
import '../online/online_question_screen.dart';
import '../online/pack_question_flow_screen.dart';
import '../profile/profile_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
  });

  @override
  State<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState
    extends State<NotificationsScreen> {
  final _store =
      NotificationStore.instance;

  final _session =
      AuthSession.instance;

  final _directory =
      UserDirectory.instance;

  final _packStore =
      QuestionPackStore.instance;

  final _questionStore =
      QuestionStore.instance;

  void _markAllAsRead() {
    final userId =
        _session.currentUser.id;

    _store.markAllAsReadForUser(
      userId,
    );
  }

  Future<void> _openPackFromNotification(
    AppNotification notification,
  ) async {
    final packId =
        notification.targetId;

    if (packId == null) {
      return;
    }

    final pack =
        _packStore.find(packId);

    if (pack == null ||
        pack.questions.isEmpty) {
      return;
    }

    final user =
        _directory.find(
      pack.publisherId,
    );

    if (user == null) {
      return;
    }

    final publisher =
        Publisher.fromUser(
      user,
      accentColor:
          AppColors.primary,
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PackQuestionFlowScreen(
          publisher:
              publisher,
          pack:
              pack,
        ),
      ),
    );
  }

  Future<void> _openQuestionNotification(
    AppNotification notification,
  ) async {
    final questionId =
        notification.targetId;

    if (questionId == null) {
      return;
    }

    final question =
        _questionStore.find(
      questionId,
    );

    if (question == null ||
        question.authorId == null) {
      return;
    }

    final user =
        _directory.find(
      question.authorId!,
    );

    if (user == null) {
      return;
    }

    final publisher =
        Publisher.fromUser(
      user,
      accentColor:
          AppColors.primary,
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OnlineQuestionScreen(
          question: question,
          publisher: publisher,
          isLastQuestion: true,
        ),
      ),
    );
  }

  void _openNotification(
    AppNotification notification,
  ) {
    _store.markAsRead(
      notification.id,
    );

    // 🐺 فتح الإشعار إشارة اهتمام قوية.
    BeastTracker.instance.notificationOpened(
      notification.id,
    );

    switch (notification.type) {
      case NotificationType.follow:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ProfileScreen(
              userId:
                  notification.actorUserId,
            ),
          ),
        );
        break;

      case NotificationType.like:
      case NotificationType.comment:
        _openQuestionNotification(
          notification,
        );
        break;

      case NotificationType.reply:
        // TODO: Open the specific comment thread
        // using parentTargetId when ready.
        _openQuestionNotification(
          notification,
        );
        break;

      case NotificationType.newQuestion:
        _openPackFromNotification(
          notification,
        );
        break;
    }
  }

  String _timeLabel(
    DateTime time,
  ) {
    final difference =
        DateTime.now().difference(time);

    if (difference.inSeconds < 60) {
      return 'الآن';
    }

    if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} د';
    }

    if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} س';
    }

    if (difference.inDays < 7) {
      return 'منذ ${difference.inDays} ي';
    }

    return 'منذ أكثر من أسبوع';
  }

  IconData _iconFor(
    NotificationType type,
  ) {
    switch (type) {
      case NotificationType.follow:
        return Icons
            .person_add_alt_1_rounded;

      case NotificationType.like:
        return Icons.favorite_rounded;

      case NotificationType.comment:
        return Icons
            .chat_bubble_outline_rounded;

      case NotificationType.reply:
        return Icons.reply_rounded;

      case NotificationType.newQuestion:
        return Icons.help_outline_rounded;
    }
  }

  Color _iconColorFor(
    NotificationType type,
  ) {
    switch (type) {
      case NotificationType.follow:
        return AppColors.secondary;

      case NotificationType.like:
        return AppColors.like;

      case NotificationType.comment:
        return AppColors.textPrimary;

      case NotificationType.reply:
        return AppColors.primary;

      case NotificationType.newQuestion:
        return AppColors.success;
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final currentUser =
            _session.currentUser;

        final notifications =
            _store.notificationsForUser(
          currentUser.id,
        );

        final unread =
            _store.unreadCountForUser(
          currentUser.id,
        );

        return Scaffold(
          backgroundColor:
              AppColors.background,

          appBar: AppBar(
            title:
                const Text('الإشعارات'),
            actions: [
              if (unread > 0)
                TextButton(
                  onPressed:
                      _markAllAsRead,
                  child:
                      const Text('قراءة الكل'),
                ),
            ],
          ),

          body: Stack(
            children: [
              const LiquidBackground(),

              SafeArea(
                child: notifications.isEmpty
                    ? const _EmptyNotifications()
                    : ListView.separated(
                        padding:
                            const EdgeInsets.fromLTRB(
                          AppSpacing.x16,
                          AppSpacing.x12,
                          AppSpacing.x16,
                          AppSpacing.x24,
                        ),
                        itemCount:
                            notifications.length,
                        separatorBuilder:
                            (_, __) =>
                                const SizedBox(
                          height:
                              AppSpacing.x8,
                        ),
                        itemBuilder:
                            (context, index) {
                          final notification =
                              notifications[index];

                          return _NotificationTile(
                            notification:
                                notification,
                            icon:
                                _iconFor(
                              notification.type,
                            ),
                            iconColor:
                                _iconColorFor(
                              notification.type,
                            ),
                            timeLabel:
                                _timeLabel(
                              notification.createdAt,
                            ),
                            onTap:
                                () =>
                                    _openNotification(
                              notification,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NotificationTile
    extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.icon,
    required this.iconColor,
    required this.timeLabel,
    required this.onTap,
  });

  final AppNotification notification;
  final IconData icon;
  final Color iconColor;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  Widget build(
    BuildContext context,
  ) {
    final isUnread =
        !notification.isRead;

    return InkWell(
      borderRadius:
          BorderRadius.circular(18),
      onTap: onTap,
      child:
          LiquidGlassContainer(
        opacity:
            isUnread ? 0.09 : 0.045,
        padding:
            const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration:
                  BoxDecoration(
                shape:
                    BoxShape.circle,
                color:
                    iconColor.withOpacity(
                  0.12,
                ),
              ),
              child: Icon(
                icon,
                size: 22,
                color:
                    iconColor,
              ),
            ),

            const SizedBox(
              width: 12,
            ),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    notification.message,
                    style:
                        AppTextStyles
                            .bodyMedium
                            .copyWith(
                      fontWeight:
                          isUnread
                              ? FontWeight.w600
                              : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(
                    height: 4,
                  ),
                  Text(
                    timeLabel,
                    style:
                        AppTextStyles
                            .caption,
                  ),
                ],
              ),
            ),

            if (isUnread)
              Container(
                width: 8,
                height: 8,
                decoration:
                    const BoxDecoration(
                  shape:
                      BoxShape.circle,
                  color:
                      AppColors.secondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotifications
    extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(
    BuildContext context,
  ) {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(
          AppSpacing.x32,
        ),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            const Icon(
              Icons
                  .notifications_none_rounded,
              size: 48,
              color:
                  AppColors.textSecondary,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              'لا توجد إشعارات بعد',
              style:
                  AppTextStyles
                      .titleMedium,
              textAlign:
                  TextAlign.center,
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'ستظهر هنا المتابعات والإعجابات والتعليقات والتحديثات الجديدة.',
              style:
                  AppTextStyles
                      .bodyMedium,
              textAlign:
                  TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
