import 'package:flutter/material.dart';

import '../services/app_state.dart';
import 'widgets.dart';
import 'chat_screen.dart';

/// 「部屋」タブ: 自分が参加している募集のグループチャット一覧（FR-3-3）
class RoomsPage extends StatelessWidget {
  const RoomsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: appState,
          builder: (context, _) {
            final rooms = appState.myRooms;
            if (rooms.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'まだ部屋がありません。\n'
                    '「近く」で募集に応募するか、自分で募集をかけて、\n'
                    '参加者が集まると部屋ができます。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: rooms.length,
              itemBuilder: (context, i) {
                final room = rooms[i];
                late final String title;
                late final String leadingId;
                if (room.isDm) {
                  final otherId = room.memberIds
                      .firstWhere((id) => id != appState.me!.id);
                  leadingId = otherId;
                  title =
                      '${appState.userById(otherId).nickname}（DM）';
                } else {
                  final rec = appState.recruitmentById(room.recruitmentId)!;
                  leadingId = rec.hostId;
                  title = rec.title;
                }
                final last = appState.lastMessageOf(room.id);
                final unread = appState.unreadByRoom[room.id] ?? 0;
                return ListTile(
                  leading: userAvatar(leadingId, size: 48),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    last.isEmpty ? '参加が決まるとメッセージが始まります' : last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: unread > 0
                      ? Badge(
                          label: Text('$unread'),
                        )
                      : Text(
                          '${room.memberIds.length}人',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChatScreen(roomId: room.id),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
