import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import 'invite_sheet.dart';
import 'widgets.dart';
import 'profile_setup_screen.dart';

/// 「マイページ」タブ: プロフィール、統計、設定（FR-4-x, FR-5-4 の受信設定）
class MyPage extends StatelessWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: appState,
          builder: (context, _) {
            final me = appState.me!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        userAvatar(me.id, size: 84, iconScale: 0.45),
                        const SizedBox(height: 12),
                        Text(me.nickname,
                            style: theme.textTheme.titleLarge!
                                .copyWith(fontWeight: FontWeight.bold)),
                        Text('${me.decade} / ${me.genderLabel}',
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final id in me.interestIds)
                              interestLabel(categoryById(id)),
                          ],
                        ),
                        if (me.bio.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            me.bio,
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    ProfileSetupScreen(existing: me),
                              ),
                            );
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('プロフィールを編集'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statCard(context, '${appState.createdCount}', '募集した数'),
                    const SizedBox(width: 8),
                    _statCard(context, '${appState.joinedRoomsCount}', '参加した部屋'),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.people_alt_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('友達を招待する'),
                    subtitle: const Text('SNSで「一緒に使いませんか？」を送る'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showInviteSheet(context),
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.mail_outline),
                        title: const Text('メールアドレス'),
                        subtitle:
                            Text(authService.sessionEmail ?? '（不明）'),
                        trailing: const Icon(Icons.verified_user_outlined),
                      ),
                      ListTile(
                        leading: const Icon(Icons.near_me),
                        title: const Text('位置情報'),
                        subtitle: Text(appState.gpsAvailable
                            ? 'GPS取得済み（距離は粗いバンド表示のみ）'
                            : '未取得（フォールバックの中心地で表示）'),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.notifications),
                        title: const Text('お知らせ通知'),
                        subtitle: const Text('自分の募集への応募・承認を通知'),
                        value: true,
                        onChanged: null, // v1 では固定 ON（本開発で設定反映）
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('ログアウト'),
                    onPressed: () {
                      authService.logout();
                      appState.detach();
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'プロトタイプについて: データは端末内のモックです（再起動でリセット）。'
                    '本開発では Supabase（Postgres + geohash / Realtime / Auth）を'
                    'バックエンドに構築し、18歳以上限定・顔アイコン禁止・'
                    '恋愛目的禁止のポリシーは規約とモデレーションで担保します。',
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: Colors.grey.shade600),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statCard(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(
                value,
                style: theme.textTheme.headlineSmall!
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
