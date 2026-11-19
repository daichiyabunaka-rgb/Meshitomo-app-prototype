import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

/// アイコン画像・投稿写真の取得と保存。
/// - モックモード: ギャラリー/カメラの画像をアプリ専用領域にコピーして永続化
/// - Supabase モード: さらに Storage の公開バケットの `<uuid>/` 配下へ
///   アップロードし、公開URLを返す（これにより他のユーザーにも画像が見える）
/// アップロードに失敗した場合は端末内パスにフォールバックする。
class IconService {
  Future<String?> pickAndSave(ImageSource source) {
    return _pickAndSave(
      source,
      subDir: 'icons',
      prefix: 'icon',
      bucket: 'icons',
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 80,
    );
  }

  /// 近況報告の投稿写真（800px・品質70。十分伝わり、容量は1/10以下）
  Future<String?> pickMealReportPhoto(ImageSource source) {
    return _pickAndSave(
      source,
      subDir: 'meal_photos',
      prefix: 'meal_report',
      bucket: 'meal-report-photos',
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 70,
    );
  }

  Future<String?> _pickAndSave(
    ImageSource source, {
    required String subDir,
    required String prefix,
    required String bucket,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
    );
    if (picked == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final targetDir =
        Directory('${dir.path}${Platform.pathSeparator}$subDir');
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }
    final ts = DateTime.now().microsecondsSinceEpoch;
    final dest =
        '${targetDir.path}${Platform.pathSeparator}${prefix}_$ts.jpg';
    File(picked.path).copySync(dest);

    if (AppConfig.useSupabase) {
      try {
        final client = Supabase.instance.client;
        final uid = client.auth.currentUser?.id;
        if (uid != null) {
          final bytes = File(dest).readAsBytesSync();
          // 共有プロジェクトでは $uid/<appId>/ 配下に置く
          // （Storageポリシーは (foldername)[1] = uid を検証するため通用する）
          final remotePath = '$uid/${AppConfig.appId}/${prefix}_$ts.jpg';
          await client.storage.from(bucket).uploadBinary(
                remotePath,
                bytes,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: true,
                ),
              );
          return client.storage.from(bucket).getPublicUrl(remotePath);
        }
      } catch (e) {
        // アップロード失敗時は端末内パスで続行（デバッグ用に記録のみ）
        debugPrint('$prefix upload failed: $e');
      }
    }
    return dest;
  }
}

/// グローバルインスタンス（本開発では DI / Riverpod Provider に置き換える）
final IconService iconService = IconService();
