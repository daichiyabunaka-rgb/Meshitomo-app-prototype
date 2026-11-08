import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// アイコン画像の取得と保存。
/// ギャラリー/カメラから選んだ画像をアプリ専用領域にコピーして永続化する
/// （image_picker の一時ファイルは消えることがあるため）。
/// 本開発では Supabase Storage へのアップロードに置き換える。
class IconService {
  Future<String?> pickAndSave(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 80,
    );
    if (picked == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final iconsDir = Directory('${dir.path}${Platform.pathSeparator}icons');
    if (!iconsDir.existsSync()) {
      iconsDir.createSync(recursive: true);
    }
    final ts = DateTime.now().microsecondsSinceEpoch;
    final dest =
        '${iconsDir.path}${Platform.pathSeparator}icon_$ts.jpg';
    File(picked.path).copySync(dest);
    return dest;
  }
}

/// グローバルインスタンス（本開発では DI / Riverpod Provider に置き換える）
final IconService iconService = IconService();
