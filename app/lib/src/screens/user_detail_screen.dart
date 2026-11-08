import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import 'chat_screen.dart';
import 'widgets.dart';

/// ユーザー詳細（プロフィール閲覧 + DM の起点）。
/// 出会い系ではなく飯とも候補として見る画面なので、募集や嗜好を主に表示する。
class UserDetailScreen extends StatelessWidget {
  const UserDetailScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = appState.userById(userId);
    final isMe = appState.me!.id == user.id;
    final recruitments = appState
        .activeRecruitments()
        .where((r) => r.hostId == user.id)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  userAvatar(user.id, size: 88, iconScale: 0.45),
                  const SizedBox(height: 12),
                  Text(
                    user.nickname,
                    style: theme.textTheme.headlineSmall!
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${user.decade} / ${user.genderLabel} / '
                    '${appState.userDistanceLabel(user)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final id in user.interestIds)
                        interestLabel(categoryById(id)),
                    ],
                  ),
                  if (user.bio.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      user.bio,
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!isMe) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('DMを始める'),
                onPressed: () {
                  final room = appState.getOrCreateDm(user.id);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatScreen(roomId: room.id),
                    ),
                  );
                },
              ),
            ),
          ],
          if (recruitments.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('この人の募集', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final r in recruitments)
              Card(
                child: ListTile(
                  leading: genreChip(r.genreId),
                  title: Text(r.title, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: Text(appState.recruitmentDistanceLabel(r)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
