import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/user_directory.dart';
import '../../core/beast/beast_tracker.dart';
import '../../core/online/feed_interaction_store.dart';
import '../../core/online/question_pack_store.dart';
import '../../core/social/follow_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/categories.dart';
import '../../data/mock_online_data.dart';
import '../../models/feed_card.dart';
import '../../models/publisher.dart';
import '../../models/question_pack.dart';
import '../../widgets/follow_button.dart';
import '../../widgets/liquid_background.dart';
import '../../widgets/liquid_glass_container.dart';
import '../../widgets/user_avatar.dart';
import '../auth/account_switch_screen.dart';
import '../online/add_question_screen.dart';
import '../online/pack_question_flow_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.userId,
  });

  final String? userId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _session = AuthSession.instance;
  final _directory = UserDirectory.instance;
  final _followStore = FollowStore.instance;
  final _packStore = QuestionPackStore.instance;
  final _feedInteractions = FeedInteractionStore.instance;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _editProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const EditProfileScreen(),
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _addQuestion() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AddQuestionScreen(),
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  void _toggleFollow(String userId) {
    final wasFollowing =
        _followStore.isFollowing(userId);

    _followStore.toggleFollow(userId);

    // 🐺 تتبع المتابعة/إلغاء المتابعة.
    if (wasFollowing) {
      BeastTracker.instance.unfollowed(
        userId: userId,
      );
    } else {
      BeastTracker.instance.followed(
        userId: userId,
      );
    }

    setState(() {});
  }

  Future<void> _openPack(QuestionPack pack) async {
    final publisherUser = _directory.find(
      pack.publisherId,
    );

    if (publisherUser == null ||
        pack.questions.isEmpty) {
      return;
    }

    final publisher = Publisher.fromUser(
      publisherUser,
      accentColor: AppColors.primary,
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PackQuestionFlowScreen(
          publisher: publisher,
          pack: pack,
        ),
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  List<FeedCard> _savedCards() {
    final savedIds = _feedInteractions.savedContentIds();

    final cards = <FeedCard>[];

    for (final pack in MockOnlineData.packs) {
      final cardId = 'pack_card_${pack.id}';

      if (!savedIds.contains(cardId)) {
        continue;
      }

      if (pack.questions.isEmpty) {
        continue;
      }

      final publisher = MockOnlineData.publishers.firstWhere(
        (item) => item.id == pack.publisherId,
      );

      cards.add(
        FeedCard(
          id: cardId,
          publisher: publisher,
          pack: pack,
          question: pack.questions.first,
        ),
      );
    }

    for (final pack in _packStore.publishedPacks) {
      final cardId = 'pack_card_${pack.id}';

      if (!savedIds.contains(cardId)) {
        continue;
      }

      if (pack.questions.isEmpty) {
        continue;
      }

      final author = _directory.find(
        pack.publisherId,
      );

      if (author == null) {
        continue;
      }

      final category = AppCategories.byId(
        pack.questions.first.categoryId,
      );

      final publisher = Publisher(
        id: author.id,
        name: author.displayName,
        handle: '@${author.username}',
        accentColor: category.color,
      );

      cards.add(
        FeedCard(
          id: cardId,
          publisher: publisher,
          pack: pack,
          question: pack.questions.first,
        ),
      );
    }

    return List.unmodifiable(cards);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _session.currentUser;
    final viewedUser = widget.userId == null ||
            widget.userId == currentUser.id
        ? currentUser
        : _directory.find(widget.userId!);

    if (viewedUser == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('الملف الشخصي'),
        ),
        body: const Center(
          child: Text(
            'لم يتم العثور على المستخدم.',
            style: AppTextStyles.bodyLarge,
          ),
        ),
      );
    }

    final isOwnProfile = viewedUser.id == currentUser.id;
    final isFollowing = _followStore.isFollowing(viewedUser.id);
    final publishedPacks = _packStore.byPublisher(viewedUser.id);
    final followerCount = viewedUser.followersCount +
        _followStore.followerCount(viewedUser.id);
    final questionCount = viewedUser.questionCount +
        publishedPacks.fold<int>(
          0,
          (sum, pack) => sum + pack.questions.length,
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(viewedUser.username),
        actions: [
          if (isOwnProfile)
            IconButton(
              tooltip: 'تبديل الحساب',
              icon: const Icon(
                Icons.swap_horiz_rounded,
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AccountSwitchScreen(),
                  ),
                );

                if (mounted) {
                  setState(() {});
                }
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          const LiquidBackground(),
          SafeArea(
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.x24,
                        AppSpacing.x16,
                        AppSpacing.x24,
                        AppSpacing.x24,
                      ),
                      child: LiquidGlassContainer(
                        padding: const EdgeInsets.all(AppSpacing.x16),
                        child: Column(
                          children: [
                            UserAvatar(
                              imageUrl: viewedUser.avatarUrl,
                              size: 96,
                            ),
                            const SizedBox(height: AppSpacing.x16),
                            Text(
                              viewedUser.displayName,
                              style: AppTextStyles.titleLarge,
                            ),
                            const SizedBox(height: AppSpacing.x4),
                            Text(
                              '@${viewedUser.username}',
                              style: AppTextStyles.username,
                            ),
                            if (viewedUser.bio.trim().isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.x12),
                              Text(
                                viewedUser.bio,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodyMedium,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.x24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _Stat(
                                  value: '$questionCount',
                                  label: 'أسئلة',
                                ),
                                _Stat(
                                  value: '$followerCount',
                                  label: 'متابعون',
                                ),
                                _Stat(
                                  value: '${viewedUser.followingCount}',
                                  label: 'يتابع',
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.x16),
                            if (isOwnProfile) ...[
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: OutlinedButton(
                                  onPressed: _editProfile,
                                  child: const Text('تعديل الملف'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton.icon(
                                  onPressed: _addQuestion,
                                  icon: const Icon(
                                    Icons.add_rounded,
                                    size: 20,
                                  ),
                                  label: const Text('إضافة سؤال'),
                                ),
                              ),
                            ] else
                              FollowButton(
                                isFollowing: isFollowing,
                                expanded: true,
                                onPressed: () =>
                                    _toggleFollow(viewedUser.id),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _ProfileTabsDelegate(
                      TabBar(
                        controller: _tabController,
                        indicatorColor: AppColors.primary,
                        labelColor: AppColors.textPrimary,
                        unselectedLabelColor: AppColors.textSecondary,
                        tabs: const [
                          Tab(text: 'المجموعات'),
                          Tab(text: 'لاحقًا'),
                          Tab(text: 'الإعجابات'),
                        ],
                      ),
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  _PublishedPacks(
                    packs: publishedPacks,
                    onTap: _openPack,
                  ),
                  _SavedQuestions(
                    cards: _savedCards(),
                    onTap: _openPack,
                  ),
                  const _ProfileEmptyState(
                    text: 'لا توجد إعجابات بعد',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublishedPacks extends StatelessWidget {
  const _PublishedPacks({
    required this.packs,
    required this.onTap,
  });

  final List<QuestionPack> packs;
  final ValueChanged<QuestionPack> onTap;

  @override
  Widget build(BuildContext context) {
    if (packs.isEmpty) {
      return const _ProfileEmptyState(
        text: 'لا توجد مجموعات منشورة بعد.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.x16),
      itemCount: packs.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.x12),
      itemBuilder: (context, index) {
        final pack = packs[index];
        final category = AppCategories.byId(
          pack.questions.first.categoryId,
        );

        return InkWell(
          onTap: () => onTap(pack),
          borderRadius: BorderRadius.circular(18),
          child: LiquidGlassContainer(
            borderRadius: 18,
            padding: const EdgeInsets.all(AppSpacing.x16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: category.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        category.name,
                        style: AppTextStyles.caption.copyWith(
                          color: category.color,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${pack.questions.length} أسئلة',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_left_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x12),
                Text(
                  pack.title,
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: AppSpacing.x8),
                Text(
                  pack.questions.first.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SavedQuestions extends StatelessWidget {
  const _SavedQuestions({
    required this.cards,
    required this.onTap,
  });

  final List<FeedCard> cards;
  final ValueChanged<QuestionPack> onTap;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const _ProfileEmptyState(
        text: 'لا توجد أسئلة محفوظة بعد.\nاضغط 🔖 على أي سؤال لتجيب عنه لاحقًا.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.x16),
      itemCount: cards.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.x12),
      itemBuilder: (context, index) {
        final card = cards[index];
        final category = AppCategories.byId(card.question.categoryId);

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onTap(card.pack),
          child: LiquidGlassContainer(
            borderRadius: 18,
            padding: const EdgeInsets.all(AppSpacing.x16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: category.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        category.name,
                        style: AppTextStyles.caption.copyWith(
                          color: category.color,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.bookmark_rounded,
                      size: 20,
                      color: AppColors.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x12),
                Text(
                  card.question.text,
                  style: AppTextStyles.bodyLarge,
                ),
                if (card.question.hashtags.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: card.question.hashtags
                        .map(
                          (hashtag) => Text(
                            '#$hashtag',
                            style: AppTextStyles.caption,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.caption,
        ),
      ],
    );
  }
}

class _ProfileEmptyState extends StatelessWidget {
  const _ProfileEmptyState({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium,
        ),
      ),
    );
  }
}

class _ProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  const _ProfileTabsDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppColors.surface,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _ProfileTabsDelegate oldDelegate) {
    return false;
  }
}
