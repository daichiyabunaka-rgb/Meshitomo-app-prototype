import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/icon_service.dart';
import '../services/location_service.dart';

const List<String> decades = ['18〜19歳', '20代', '30代', '40代', '50代以上'];

/// プロフィール登録・編集（FR-1-2, FR-1-3, FR-4-1）
/// - 会員登録モード: registrationEmail / registrationPassword を渡す（メール認証付きで登録）
/// - 編集モード: existing を渡す
/// 顔写真は不可。アイコンは用意された「趣味アイコンセット」から選ぶ。
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    this.existing,
    this.registrationEmail,
    this.registrationPassword,
  });

  final AppUser? existing;
  final String? registrationEmail;
  final String? registrationPassword;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController _nickname;
  late final TextEditingController _bio;
  late String _decade;
  late String _gender;
  late String _iconCategory;
  late final Set<String> _interests;
  // アイコン画像（投稿）。null=未選択（既定の趣味アイコンを使う）, ''=解除
  String? _iconImagePath;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nickname = TextEditingController(text: e?.nickname ?? '');
    _bio = TextEditingController(text: e?.bio ?? '');
    _decade = e?.decade ?? '20代';
    _gender = e?.gender ?? 'undisclosed';
    _iconCategory = e?.iconCategoryId ?? 'ramen';
    _interests = <String>{...?e?.interestIds};
    _iconImagePath = (e?.iconImagePath?.isNotEmpty ?? false)
        ? e!.iconImagePath
        : null;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _bio.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _nickname.text.trim().isNotEmpty &&
      _interests.isNotEmpty &&
      _iconCategory.isNotEmpty;

  Future<void> _pickImage(ImageSource source) async {
    final path = await iconService.pickAndSave(source);
    if (path != null) {
      setState(() => _iconImagePath = path);
    }
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);
    final nickname = _nickname.text.trim();
    final bio = _bio.text.trim();
    final imagePath =
        (_iconImagePath == null || _iconImagePath!.isEmpty) ? null : _iconImagePath;

    if (widget.existing == null) {
      // 会員登録（この時点でアカウント作成 + 自動ログイン + 位置情報取得）
      try {
        final gps = await locationService.currentPosition();
        if (gps != null) {
          appState.applyGps(gps.$1, gps.$2);
        }
        authService.register(
          email: widget.registrationEmail!,
          password: widget.registrationPassword!,
          nickname: nickname,
          decade: _decade,
          gender: _gender,
          iconCategoryId: _iconCategory,
          interestIds: _interests.toList(),
          bio: bio,
          iconImagePath: imagePath,
        );
        final user = authService.buildSessionUser(
          lat: gps?.$1 ?? appState.anchorLat,
          lng: gps?.$2 ?? appState.anchorLng,
        );
        appState.attachUser(user!, reseed: true);
      } on AuthException catch (e) {
        if (mounted) {
          setState(() {
            _submitting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    } else {
      authService.updateCurrentProfile(
        iconImagePath: _iconImagePath, // null=変更なし, ''=解除, パス=新画像
      );
      appState.updateProfile(
        nickname: nickname,
        decade: _decade,
        gender: _gender,
        iconCategoryId: _iconCategory,
        interestIds: _interests.toList(),
        bio: bio,
        iconImagePath: _iconImagePath,
      );
    }
    if (mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'プロフィール編集' : 'プロフィール登録'),
        actions: [
          TextButton(
            onPressed: (_isValid && !_submitting) ? _submit : null,
            child: Text(isEdit ? '保存' : '登録'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('ニックネーム', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _nickname,
            decoration: const InputDecoration(
              hintText: '例: 麺活さとる',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            maxLength: 20,
          ),
          const SizedBox(height: 8),
          Text('年代', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final d in decades)
                ChoiceChip(
                  label: Text(d),
                  selected: _decade == d,
                  onSelected: (_) => setState(() => _decade = d),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('性別', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'male', label: Text('男性')),
              ButtonSegment(value: 'female', label: Text('女性')),
              ButtonSegment(value: 'undisclosed', label: Text('非公開')),
            ],
            selected: {_gender},
            onSelectionChanged: (s) => setState(() => _gender = s.first),
          ),
          const SizedBox(height: 16),
          Text('アイコン', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '料理や店の写真など、趣味に関係する画像を投稿できます。'
            '顔が写った画像は使用できません（本開発では AI 審査で自動拒否します）。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _iconPreview(theme),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('ギャラリーから'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('カメラで撮影'),
                    ),
                    if (_iconImagePath != null &&
                        _iconImagePath!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            setState(() => _iconImagePath = ''),
                        child: const Text('画像をやめて趣味アイコンに戻す'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('画像がない場合の趣味アイコン', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in interestCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () => setState(() => _iconCategory = c.id),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.colorScheme.primaryContainer,
                              border: _iconCategory == c.id
                                  ? Border.all(
                                      color: theme.colorScheme.primary,
                                      width: 3,
                                    )
                                  : null,
                            ),
                            child: Icon(
                              c.icon,
                              size: 32,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.label,
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('興味カテゴリ（複数選択）', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in interestCategories)
                FilterChip(
                  avatar: Icon(c.icon, size: 18),
                  label: Text(c.label),
                  selected: _interests.contains(c.id),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _interests.add(c.id);
                    } else {
                      _interests.remove(c.id);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('自己紹介（飯ともステータス）', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '好きなもの、苦手なもの、どういう時に誘いたいか等。中身で選んでもらうための情報です。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bio,
            maxLines: 4,
            maxLength: 140,
            decoration: const InputDecoration(
              hintText:
                  '例: 平日夜のラーメンと土曜のブランチが好き。ひとり飯もするけど、同じ趣味の人と行くと倍くらい美味しい。',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _iconPreview(ThemeData theme) {
    final cat = categoryById(_iconCategory);
    Widget preview;
    if (_iconImagePath != null && _iconImagePath!.isNotEmpty) {
      final f = File(_iconImagePath!);
      preview = f.existsSync()
          ? ClipOval(
              child: Image.file(f, width: 88, height: 88, fit: BoxFit.cover))
          : Icon(cat.icon, size: 40, color: theme.colorScheme.primary);
    } else {
      preview = Icon(cat.icon, size: 40, color: theme.colorScheme.primary);
    }
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primaryContainer,
      ),
      child: Center(child: preview),
    );
  }
}
