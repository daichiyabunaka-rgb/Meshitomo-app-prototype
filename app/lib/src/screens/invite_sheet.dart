import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_state.dart';
import '../util/share_text.dart';

/// 友達招待シート: SNS共有 / テキストコピー（みんなも一緒に使いませんか？）
Future<void> showInviteSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final me = appState.me!;
      final text = inviteText(me.nickname);
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '友達を招待',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleLarge!
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'LINE / X / Instagram など、お使いの SNS やメッセージアプリから'
              '招待状を送れます。',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(sheetContext).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                text,
                style:
                    const TextStyle(height: 1.5),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.ios_share),
                label: const Text('SNS・メッセージで共有'),
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await SharePlus.instance.share(
                      ShareParams(
                        title: '飯とも！',
                        text: text,
                      ),
                    );
                  } catch (_) {
                    // 共有シートを開けない端末では無視する（デモのため）
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('テキストをコピー'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('招待文をコピーしました'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '本開発では招待リンク（?ref=コード）から登録すると招待者と自動で'
              '繋がる機能を追加予定です。',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
          ],
        ),
      );
    },
  );
}
