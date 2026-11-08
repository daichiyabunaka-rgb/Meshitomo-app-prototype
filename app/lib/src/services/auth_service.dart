import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// メール認証サービス（プロトタイプは端末内モック、本開発で Supabase Auth に差し替える）。
/// アカウントとセッションは SharedPreferences に保存され、アプリ再起動後も
/// ログイン状態が維持される。パスワードは SHA-256 でハッシュ化（テスト用の簡易実装。
/// 本開発では Supabase 側の bcrypt/scrypt を使う）。
class AuthService extends ChangeNotifier {
  static const _kAccounts = 'meshitomo_accounts';
  static const _kSession = 'meshitomo_session';

  final Map<String, _Account> _accounts = {}; // key: email (小文字化)
  String? _sessionEmail;
  bool initialized = false;

  String? get sessionEmail => _sessionEmail;
  bool get hasSession => _sessionEmail != null;

  Future<void> init() async {
    if (initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kAccounts) ?? const [];
    for (final json in raw) {
      try {
        final acc = _Account.fromJson(jsonDecode(json) as Map<String, dynamic>);
        _accounts[acc.email] = acc;
      } catch (_) {
        // 壊れたレコードは読み飛ばす
      }
    }
    final saved = prefs.getString(_kSession);
    if (saved != null && _accounts.containsKey(saved)) {
      _sessionEmail = saved;
    }
    initialized = true;
    notifyListeners();
  }

  String _hash(String email, String password) {
    final digest = sha256.convert(utf8.encode('meshitomo-v1:$email:$password'));
    return digest.toString();
  }

  bool _exists(String email) => _accounts.containsKey(email.toLowerCase());

  /// 会員登録（成功すると同時にログインする）
  void register({
    required String email,
    required String password,
    required String nickname,
    required String decade,
    required String gender,
    required String iconCategoryId,
    required List<String> interestIds,
    required String bio,
  }) {
    final key = email.trim().toLowerCase();
    if (_exists(key)) {
      throw AuthException('このメールアドレスは既に登録されています');
    }
    final acc = _Account(
      id: 'acc-${_accounts.length + 1}',
      email: key,
      passwordHash: _hash(key, password),
      nickname: nickname,
      decade: decade,
      gender: gender,
      iconCategoryId: iconCategoryId,
      interestIds: interestIds,
      bio: bio,
    );
    _accounts[key] = acc;
    _sessionEmail = key;
    _persist();
    notifyListeners();
  }

  /// ログイン
  void login(String email, String password) {
    final key = email.trim().toLowerCase();
    final acc = _accounts[key];
    if (acc == null || acc.passwordHash != _hash(key, password)) {
      throw AuthException('メールアドレスまたはパスワードが違います');
    }
    _sessionEmail = key;
    _persist();
    notifyListeners();
  }

  /// ログアウト（アカウントは残る）
  void logout() {
    _sessionEmail = null;
    _persist();
    notifyListeners();
  }

  /// セッション中のユーザーのプロフィールを AppUser に変換して返す
  AppUser? buildSessionUser({
    required double lat,
    required double lng,
  }) {
    final email = _sessionEmail;
    if (email == null) return null;
    final acc = _accounts[email];
    if (acc == null) return null;
    return AppUser(
      id: acc.id,
      nickname: acc.nickname,
      decade: acc.decade,
      gender: acc.gender,
      iconCategoryId: acc.iconCategoryId,
      interestIds: acc.interestIds,
      bio: acc.bio,
      lat: lat,
      lng: lng,
    );
  }

  /// ログイン中のアカウントのプロフィール更新（本人確認用の email 表示にも使う）
  String? sessionNickname() {
    final email = _sessionEmail;
    if (email == null) return null;
    return _accounts[email]?.nickname;
  }

  void _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kAccounts,
        _accounts.values.map((a) => jsonEncode(a.toJson())).toList());
    if (_sessionEmail == null) {
      await prefs.remove(_kSession);
    } else {
      await prefs.setString(_kSession, _sessionEmail!);
    }
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class _Account {
  final String id;
  final String email;
  final String passwordHash;
  final String nickname;
  final String decade;
  final String gender;
  final String iconCategoryId;
  final List<String> interestIds;
  final String bio;

  _Account({
    required this.id,
    required this.email,
    required this.passwordHash,
    required this.nickname,
    required this.decade,
    required this.gender,
    required this.iconCategoryId,
    required this.interestIds,
    required this.bio,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'passwordHash': passwordHash,
        'nickname': nickname,
        'decade': decade,
        'gender': gender,
        'iconCategoryId': iconCategoryId,
        'interestIds': interestIds,
        'bio': bio,
      };

  factory _Account.fromJson(Map<String, dynamic> j) => _Account(
        id: j['id'] as String,
        email: j['email'] as String,
        passwordHash: j['passwordHash'] as String,
        nickname: j['nickname'] as String,
        decade: j['decade'] as String,
        gender: j['gender'] as String,
        iconCategoryId: j['iconCategoryId'] as String,
        interestIds: (j['interestIds'] as List).cast<String>(),
        bio: j['bio'] as String,
      );
}

/// グローバルインスタンス（本開発では DI / Riverpod Provider に置き換える）
final AuthService authService = AuthService();
