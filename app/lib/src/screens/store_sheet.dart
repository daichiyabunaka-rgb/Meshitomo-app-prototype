import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/app_state.dart';
import 'ai_concierge_screen.dart';
import 'map_screen.dart';
import 'widgets.dart';

/// 店舗（ビジネスユーザー）の詳細シート。「近く」とマップ画面の両方から使う。
/// クーポン機能は廃止（2026-02 方針変更）。店舗情報・マップ連携・AI接客を提供する。
Future<void> showStoreSheet(BuildContext context, BusinessUser store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      builder: (sheetContext, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                userAvatar(store.id, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store.nickname,
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleMedium!
                              .copyWith(fontWeight: FontWeight.bold)),
                      Text(
                          '${store.storeType} / ${appState.userDistanceLabel(store)}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(store.bio),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('マップ'),
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MapScreen(highlightStoreId: store.id),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Googleマップ'),
                    onPressed: () =>
                        openInGoogleMaps(store),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.smart_toy_outlined),
                label: const Text('AI接客に話しかける'),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AiConciergeScreen(storeId: store.id),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI接客はビジネスユーザー向けの有料機能（デモ）。'
              '本開発では LLM を接続し、来店前の質問対応・営業文の作成支援を提供します。',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Google マップアプリ/ブラウザで店舗の場所を開く（APIキー不要の標準URL）。
/// 本開発では Google Maps SDK（Google Cloud の API キー）に置き換えて、
/// アプリ内で経路案内まで表示できるようにする予定。
Future<void> openInGoogleMaps(BusinessUser store) async {
  final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${store.lat},${store.lng}');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // 端末に開けるアプリがない場合は何もしない（デモのため）
  }
}
