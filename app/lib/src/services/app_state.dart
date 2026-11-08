import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mock/mock_data.dart';
import '../models.dart';
import '../util/format.dart';

/// アプリ全体の状態。プロトタイプでは募集・部屋などのドメイン状態はインメモリ。
/// 認証（アカウント・セッション）は AuthService が担い、このクラスは
/// 「ログイン中のユーザー」だけを知る。本開発で Supabase 実装に差し替える境界。
class AppState extends ChangeNotifier {
  AppUser? me;
  bool gpsAvailable = false;
  double anchorLat = 35.6812; // デフォルトは東京駅（GPS が取れない場合のフォールバック）
  double anchorLng = 139.7671;

  final Map<String, AppUser> _users = {};
  final List<Recruitment> _recruitments = [];
  final List<JoinApplication> _applications = [];
  final List<ChatRoom> _rooms = [];
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, int> unreadByRoom = {};

  int _seq = 1;
  bool _closed = false;
  bool _seeded = false;

  AppState() {
    _rebuildMockUsers();
  }

  // ---------------------------------------------------------------- basics

  DateTime _now() => DateTime.now();

  AppUser userById(String id) => _users[id]!;

  Recruitment? recruitmentById(String id) {
    for (final r in _recruitments) {
      if (r.id == id) return r;
    }
    return null;
  }

  ChatRoom? roomById(String id) {
    for (final r in _rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  List<AppUser> get allUsers => _users.values.toList();

  /// 近くの一般ユーザー（自分以外、ビジネス除く）
  List<AppUser> get generalUsers {
    if (me == null) return const [];
    return _users.values
        .where((u) => u.id != me!.id && !u.isBusiness)
        .toList();
  }

  /// 近くのビジネスユーザー（店舗）
  List<BusinessUser> get businessUsers {
    return _users.values.whereType<BusinessUser>().toList();
  }

  void _rebuildMockUsers() {
    final users = buildMockUsers(anchorLat, anchorLng);
    _users
      ..clear()
      ..addEntries(users.map((u) => MapEntry(u.id, u)));
    if (me != null) {
      _users[me!.id] = me!;
    }
  }

  /// 実 GPS で現在地を更新（モックユーザーが現在地の周囲に再配置される）
  void applyGps(double lat, double lng) {
    gpsAvailable = true;
    anchorLat = lat;
    anchorLng = lng;
    _rebuildMockUsers();
    if (me != null) {
      final old = me!;
      me = AppUser(
        id: old.id,
        nickname: old.nickname,
        decade: old.decade,
        gender: old.gender,
        iconCategoryId: old.iconCategoryId,
        interestIds: old.interestIds,
        bio: old.bio,
        lat: lat,
        lng: lng,
        iconImagePath: old.iconImagePath,
      );
      _users[me!.id] = me!;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ account

  /// ログイン／会員登録後に呼ばれ、ドメイン状態を初期化する
  void attachUser(AppUser user, {bool reseed = false}) {
    me = user;
    _users[me!.id] = me!;
    if (reseed || !_seeded) {
      _recruitments.clear();
      _recruitments.addAll(seedRecruitments(_now(), _users.values
          .where((u) => u.id != me!.id && !u.isBusiness)
          .toList()));
      _seeded = true;
    }
    notifyListeners();
  }

  /// ログアウト
  void detach() {
    me = null;
    notifyListeners();
  }

  void updateProfile({
    required String nickname,
    required String decade,
    required String gender,
    required String iconCategoryId,
    required List<String> interestIds,
    required String bio,
    String? iconImagePath,
  }) {
    final old = me!;
    me = AppUser(
      id: old.id,
      nickname: nickname,
      decade: decade,
      gender: gender,
      iconCategoryId: iconCategoryId,
      interestIds: interestIds,
      bio: bio,
      lat: old.lat,
      lng: old.lng,
      iconImagePath: iconImagePath,
    );
    _users[me!.id] = me!;
    notifyListeners();
  }

  // ------------------------------------------------------------ recruit

  /// 近くのアクティブな募集（距離近い順）。未ログインなら空。
  List<Recruitment> activeRecruitments({String? genreId}) {
    if (me == null) return const [];
    final now = _now();
    final list = _recruitments
        .where((r) => r.isActiveAt(now))
        .toList()
      ..sort((a, b) {
        final da = haversineKm(
            me!.lat, me!.lng, _users[a.hostId]!.lat, _users[a.hostId]!.lng);
        final db = haversineKm(
            me!.lat, me!.lng, _users[b.hostId]!.lat, _users[b.hostId]!.lng);
        return da.compareTo(db);
      });
    if (genreId == null) return list;
    return list.where((r) => r.genreId == genreId).toList();
  }

  /// 募集までの粗い距離バンド
  String recruitmentDistanceLabel(Recruitment r) {
    if (r.hostId == me!.id) return 'あなたの募集';
    final km = haversineKm(
        me!.lat, me!.lng, _users[r.hostId]!.lat, _users[r.hostId]!.lng);
    return distanceLabel(km);
  }

  /// ユーザー（一般・ビジネス）までの粗い距離バンド
  String userDistanceLabel(AppUser u) {
    final mine = me;
    if (mine == null) return '';
    return distanceLabel(haversineKm(mine.lat, mine.lng, u.lat, u.lng));
  }

  Recruitment createRecruitment({
    required String genreId,
    required String title,
    required String body,
    required String meetup,
    required int capacity,
    required int expiryHours,
  }) {
    final now = _now();
    final rec = Recruitment(
      id: 'r-${_seq++}',
      hostId: me!.id,
      genreId: genreId,
      title: title,
      body: body,
      meetup: meetup,
      capacity: capacity,
      createdAt: now,
      expiresAt: now.add(Duration(hours: expiryHours)),
      memberIds: [me!.id],
    );
    _recruitments.insert(0, rec);
    notifyListeners();
    _scheduleMockApplicants(rec);
    return rec;
  }

  /// デモ用: 自分の募集にモックユーザーが数秒後に応募してくる
  void _scheduleMockApplicants(Recruitment rec) {
    final candidates = _users.values
        .where((u) =>
            u.id != me!.id && !u.isBusiness && u.interestIds.isNotEmpty)
        .toList();
    if (candidates.isEmpty) return;
    _fakeDelay(const Duration(seconds: 4), () {
      final alive = recruitmentById(rec.id);
      if (alive == null ||
          !alive.isActiveAt(_now()) ||
          _applications.any((a) =>
              a.recruitmentId == rec.id &&
              a.applicantId == candidates.first.id)) {
        return;
      }
      _addApplication(
        recruitmentId: rec.id,
        applicantId: candidates.first.id,
        message: mockApplyMessages.first,
      );
    });
    if (candidates.length > 1) {
      _fakeDelay(const Duration(seconds: 12), () {
        final alive = recruitmentById(rec.id);
        if (alive == null || !alive.isActiveAt(_now())) return;
        final already = _applications.any((a) =>
            a.recruitmentId == rec.id && a.applicantId == candidates[1].id);
        if (already) return;
        _addApplication(
          recruitmentId: rec.id,
          applicantId: candidates[1].id,
          message: mockApplyMessages[1 % mockApplyMessages.length],
        );
      });
    }
  }

  void _addApplication({
    required String recruitmentId,
    required String applicantId,
    required String message,
  }) {
    if (_closed) return;
    _applications.add(JoinApplication(
      id: 'a-${_seq++}',
      recruitmentId: recruitmentId,
      applicantId: applicantId,
      message: message,
      status: JoinStatus.pending,
      createdAt: _now(),
    ));
    notifyListeners();
  }

  List<JoinApplication> applicationsFor(String recruitmentId) {
    return _applications
        .where((a) => a.recruitmentId == recruitmentId)
        .toList();
  }

  JoinApplication? myPendingApplication(String recruitmentId) {
    for (final a in _applications) {
      if (a.recruitmentId == recruitmentId &&
          a.applicantId == me!.id &&
          a.status == JoinStatus.pending) {
        return a;
      }
    }
    return null;
  }

  void applyTo(String recruitmentId, {required String message}) {
    final rec = recruitmentById(recruitmentId);
    if (rec == null || rec.hostId == me!.id) return;
    if (myPendingApplication(recruitmentId) != null) return;
    _addApplication(
      recruitmentId: recruitmentId,
      applicantId: me!.id,
      message: message,
    );
    // デモ用: 数秒後にホストが承認する
    _fakeDelay(const Duration(seconds: 3), () {
      final app = myPendingApplication(recruitmentId);
      if (app == null) return;
      _acceptInternal(app);
    });
  }

  void acceptApplication(String applicationId) {
    JoinApplication? target;
    for (final a in _applications) {
      if (a.id == applicationId) target = a;
    }
    if (target == null || target.status != JoinStatus.pending) return;
    _acceptInternal(target);
  }

  void declineApplication(String applicationId) {
    for (final a in _applications) {
      if (a.id == applicationId) a.status = JoinStatus.declined;
    }
    notifyListeners();
  }

  void _acceptInternal(JoinApplication app) {
    if (_closed) return;
    final rec = recruitmentById(app.recruitmentId);
    if (rec == null || rec.isFull || !rec.isActiveAt(_now())) return;
    if (app.status != JoinStatus.pending) return;

    app.status = JoinStatus.accepted;
    final updated = Recruitment(
      id: rec.id,
      hostId: rec.hostId,
      genreId: rec.genreId,
      title: rec.title,
      body: rec.body,
      meetup: rec.meetup,
      capacity: rec.capacity,
      createdAt: rec.createdAt,
      expiresAt: rec.expiresAt,
      memberIds: [...rec.memberIds, app.applicantId],
    );
    final idx = _recruitments.indexWhere((r) => r.id == rec.id);
    _recruitments[idx] = updated;

    final room = _ensureRoomFor(updated);
    _postMessage(room.id,
        senderId: 'system',
        body: '${_users[app.applicantId]!.nickname} さんが参加しました。',
        isSystem: true);
    unreadByRoom[room.id] = (unreadByRoom[room.id] ?? 0) + 1;
    notifyListeners();

    // デモ用: 参加者がひとこと挨拶する
    if (app.applicantId != me!.id) {
      _fakeDelay(const Duration(seconds: 2), () {
        _postMessage(room.id,
            senderId: app.applicantId,
            body: mockReplies[2 % mockReplies.length]);
        unreadByRoom[room.id] = (unreadByRoom[room.id] ?? 0) + 1;
        notifyListeners();
      });
    }
  }

  ChatRoom _ensureRoomFor(Recruitment rec) {
    for (final room in _rooms) {
      if (room.recruitmentId == rec.id) return room;
    }
    final room = ChatRoom(
      id: 'room-${_seq++}',
      recruitmentId: rec.id,
      memberIds: List.of(rec.memberIds),
      createdAt: _now(),
      type: 'group',
    );
    _rooms.insert(0, room);
    _messages[room.id] = [];
    return room;
  }

  // ------------------------------------------------------------ rooms / DM

  List<ChatRoom> get myRooms {
    return _rooms
        .where((r) => me != null && r.memberIds.contains(me!.id))
        .toList();
  }

  List<ChatMessage> messagesOf(String roomId) => _messages[roomId] ?? const [];

  String lastMessageOf(String roomId) {
    final list = _messages[roomId];
    if (list == null || list.isEmpty) return '';
    return list.last.body;
  }

  void markRoomRead(String roomId) {
    unreadByRoom[roomId] = 0;
    notifyListeners();
  }

  /// 特定ユーザーとの DM ルームを取得（なければ作る）
  ChatRoom getOrCreateDm(String otherUserId) {
    for (final room in _rooms) {
      if (room.isDm &&
          room.memberIds.contains(me!.id) &&
          room.memberIds.contains(otherUserId)) {
        return room;
      }
    }
    final room = ChatRoom(
      id: 'dm-${_seq++}',
      recruitmentId: '',
      memberIds: [me!.id, otherUserId],
      createdAt: _now(),
      type: 'dm',
    );
    _rooms.insert(0, room);
    _messages[room.id] = [];
    _postMessage(room.id,
        senderId: 'system',
        body:
            '${_users[otherUserId]!.nickname} さんとのDMを始めました。',
        isSystem: true);
    notifyListeners();
    return room;
  }

  void sendMessage(String roomId, String body) {
    _postMessage(roomId, senderId: me!.id, body: body);
    notifyListeners();
    // デモ用: 他の参加者が返信する
    final room = roomById(roomId);
    if (room == null) return;
    final others = room.memberIds.where((id) => id != me!.id).toList();
    if (others.isEmpty || others.every((id) => id == 'system')) return;
    _fakeDelay(const Duration(seconds: 3), () {
      _postMessage(roomId,
          senderId: others.first,
          body: mockReplies[_seq % mockReplies.length]);
      notifyListeners();
    });
  }

  void _postMessage(String roomId,
      {required String senderId, required String body, bool isSystem = false}) {
    if (_closed) return;
    _messages.putIfAbsent(roomId, () => []);
    _messages[roomId]!.add(ChatMessage(
      id: 'm-${_seq++}',
      roomId: roomId,
      senderId: senderId,
      body: body,
      sentAt: _now(),
      isSystem: isSystem,
    ));
  }

  // ------------------------------------------------------------ stats

  int get createdCount => _recruitments.where((r) => r.hostId == me!.id).length;

  int get joinedRoomsCount => myRooms.length;

  void _fakeDelay(Duration d, void Function() fn) {
    Future.delayed(d, () {
      if (!_closed) fn();
    });
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}

/// グローバルインスタンス（本開発では DI / Riverpod Provider に置き換える）
final AppState appState = AppState();
