import 'package:flutter/material.dart';

import '../../core/social/comment_store.dart';
import '../../core/beast/beast_tracker.dart';
import '../../core/social/question_social_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/question.dart';
import '../liquid_glass_container.dart';
import 'social_comment_card.dart';
import 'social_reply_thread_sheet.dart';

class SocialCommentSheet {
  SocialCommentSheet._();

  static Future<void> show(
    BuildContext context, {
    required Question question,
    VoidCallback? onChanged,
    String? focusCommentId,
  }) async {
    final controller = TextEditingController();
    String? replyToCommentId;
    bool didAutoOpenThread = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (sheetContext) {
        return ListenableBuilder(
          listenable: CommentStore.instance,
          builder: (context, _) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                final rootComments =
                    CommentStore.instance.rootComments(
                  question.id,
                );

                if (focusCommentId != null &&
                    !didAutoOpenThread) {
                  didAutoOpenThread = true;

                  final targetComment =
                      CommentStore.instance.findById(
                    focusCommentId,
                  );

                  if (targetComment != null) {
                    // The notification points at the parent
                    // comment id. If it's itself a reply,
                    // resolve up to its root parent so the
                    // thread sheet has the correct anchor.
                    final rootTarget =
                        targetComment.parentCommentId == null
                            ? targetComment
                            : CommentStore.instance.findById(
                                    targetComment.parentCommentId!,
                                  ) ??
                                  targetComment;

                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) {
                        SocialReplyThreadSheet.show(
                          sheetContext,
                          parentComment: rootTarget,
                        );
                      },
                    );
                  }
                }

                void submitComment() {
                  final text = controller.text.trim();

                  if (text.isEmpty) {
                    return;
                  }

                  final parentId = replyToCommentId;

                  final comment =
                      CommentStore.instance.add(
                    questionId: question.id,
                    text: text,
                    parentCommentId: parentId,
                  );

                  if (parentId == null) {
                    // 🐺 تعليق جديد على المحتوى.
                    BeastTracker.instance.commented(
                      itemId: question.id,
                      text: text,
                      creatorId: question.authorId,
                    );

                    QuestionSocialService.instance.notifyComment(
                      question: question,
                      comment: comment,
                    );
                  } else {
                    final parent =
                        CommentStore.instance.findById(
                      parentId,
                    );

                    // 🐺 رد على تعليق.
                    BeastTracker.instance.replied(
                      itemId: question.id,
                      creatorId: question.authorId,
                      parentCommentId: parentId,
                    );

                    if (parent != null) {
                      QuestionSocialService.instance.notifyReply(
                        parentComment: parent,
                        reply: comment,
                      );
                    }
                  }

                  controller.clear();

                  setSheetState(() {
                    replyToCommentId = null;
                  });

                  onChanged?.call();
                }

                return SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top: 12,
                      bottom:
                          MediaQuery.of(context).viewInsets.bottom + 12,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.96),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                          bottom: Radius.circular(28),
                        ),
                        border: Border.all(
                          color: AppColors.titaniumBorder.withOpacity(0.55),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 30,
                            offset: Offset(0, -8),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.72,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Container(
                                width: 42,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppColors.textSecondary
                                      .withOpacity(0.45),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Text(
                                    'التعليقات',
                                    style: AppTextStyles.titleMedium,
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${CommentStore.instance.countForQuestion(question.id)}',
                                    style: AppTextStyles.caption,
                                  ),
                                ],
                              ),
                              if (replyToCommentId != null) ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: AppColors.primary
                                          .withOpacity(0.35),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.reply_rounded,
                                        size: 18,
                                        color: AppColors.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          'الرد على التعليق',
                                          style: AppTextStyles.caption,
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          setSheetState(() {
                                            replyToCommentId = null;
                                          });
                                        },
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Expanded(
                                child: rootComments.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'لا توجد تعليقات بعد.\nكن أول من يشارك رأيه.',
                                          textAlign: TextAlign.center,
                                          style: AppTextStyles.bodyMedium,
                                        ),
                                      )
                                    : ListView.separated(
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior
                                                .onDrag,
                                        itemCount: rootComments.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 10),
                                        itemBuilder: (_, index) {
                                          final comment =
                                              rootComments[index];

                                          return SocialCommentCard(
                                            comment: comment,
                                            onReply: () {
                                              setSheetState(() {
                                                replyToCommentId =
                                                    comment.id;
                                              });
                                            },
                                            onLike: () {
                                              onChanged?.call();
                                            },
                                          );
                                        },
                                      ),
                              ),
                              const SizedBox(height: 12),
                              LiquidGlassContainer(
                                opacity: 0.08,
                                borderRadius: 20,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: controller,
                                        maxLength: 500,
                                        minLines: 1,
                                        maxLines: 4,
                                        textInputAction: TextInputAction.send,
                                        style: AppTextStyles.bodyMedium
                                            .copyWith(
                                          color: AppColors.textPrimary,
                                        ),
                                        cursorColor: AppColors.primary,
                                        decoration: InputDecoration(
                                          hintText: replyToCommentId == null
                                              ? 'اكتب تعليقك...'
                                              : 'اكتب ردك...',
                                          hintStyle: AppTextStyles.bodyMedium
                                              .copyWith(
                                            color: AppColors.textSecondary
                                                .withOpacity(0.72),
                                          ),
                                          counterText: '',
                                          filled: false,
                                          fillColor: Colors.transparent,
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          errorBorder: InputBorder.none,
                                          focusedErrorBorder:
                                              InputBorder.none,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 10,
                                          ),
                                        ),
                                        onSubmitted: (_) => submitComment(),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: submitComment,
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        child: Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withOpacity(0.14),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                              color: AppColors.primary
                                                  .withOpacity(0.45),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.send_rounded,
                                            size: 20,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    controller.dispose();
  }
}
