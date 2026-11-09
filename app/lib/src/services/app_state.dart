import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mock/mock_data.dart';
import '../models.dart';
import '../util/format.dart';
import 'app_config.dart';
import 'supabase_data.dart';

/// アプリ全体の状態。
/// - モックモード: ドメイン状態はインメモリ（モックユーザーが自動で応募・返信する）
/// - Supabase モード（--dart-define でキー指定）: 募集・応募・チャット・DM は
///   実データ。モックの自動応答は無効化される。
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
  bool _remoteBusy = false;

  bool get _remote => AppConfig.useSupabase;

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

  /// 実 GPS で現在地を更新（モックユーザーが現在地の周囲に再配置される）。
  /// Supabase モードでは自分の位置 geohash を DB に反映して近傍を引き直す。
  void applyGps(double lat, double lng) {
    gpsAvailable = true;
    anchorLat = lat;
    anchorLng = lng;
    _rebuildMockUsers();
    if (me != null) {
      me = me!.withPosition(lat, lng);
      _users[me!.id] = me!;
    }
    notifyListeners();
    if (_remote && me != null) {
      unawaited(refreshFromRemote());
    }
  }

  // ------------------------------------------------------------ account

  /// ログイン／会員登録後に呼ばれ、ドメイン状態を初期化する
  void attachUser(AppUser user, {bool reseed = false}) {
    me = user;
    _users[me!.id] = me!;
    if (_remote) {
      // Supabase モード: モックのシードは作らず実データを引きに行く
      unawaited(refreshFromRemote());
      _seeded = true;
    } else if (reseed || !_seeded) {
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

  /// Supabase モード: 近くの人・募集・応募・部屋を実データから引き直す
  Future<void> refreshFromRemote() async {
    if (me == null || !AppConfig.useSupabase || _remoteBusy) return;
    _remoteBusy = true;
    try {
      await supabaseData.updateMyLocation(me!.lat, me!.lng);
      final (users, recsHosts) = await (
        supabaseData.fetchNearbyUsers(me!),
        supabaseData.fetchActiveRecruitments(me!)
      ).wait;
      // ユーザーマップを再構築（自分 + 実データ。モックは使わない）
      _users
        ..clear()
        ..addEntries(users.map((u) => MapEntry(u.id, u)));
      if (me != null) {
        _users[me!.id] = me!;
      }
      for (final h in recsHosts.$2) {
        _users[h.id] = h;
      }
      _recruitments
        ..clear()
        ..addAll(recsHosts.$1);
      // 自分の募集への応募
      final myRecs = _recruitments.where((r) => r.hostId == me!.id).toList();
      final (hostApps, appUsers) =
          await supabaseData.fetchHostApplications(myRecs);
      final myApps = await supabaseData.fetchMyApplications();
      _applications
        ..clear()
        ..addAll(hostApps)
        ..addAll(myApps);
      for (final u in appUsers) {
        _users[u.id] = u;
        // 応募者が募集に既に参加している場合（承認済み）に対応
      }
      // 承認済みの member_ids を募集に反映
      for (final app in _applications) {
        if (app.status == JoinStatus.accepted) {
          final rec = _recruitments.any((r) => r.id == app.recruitmentId)
              ? _recruitments.firstWhere((r) => r.id == app.recruitmentId)
              : null;
          if (rec != null && !rec.memberIds.contains(app.applicantId)) {
            final idx = _recruitments.indexOf(rec);
            _recruitments[idx] = Recruitment(
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
          }
        }
      }
      // 部屋
      final rooms = await supabaseData.fetchMyRooms();
      for (final room in rooms) {
        final exists = _rooms.any((r) => r.id == room.id);
        if (!exists) {
          _rooms.add(room);
          _messages.putIfAbsent(room.id, () => []);
        }
      }
      notifyListeners();
    } catch (_) {
      // ベータ: 通信エラーは画面を壊さず無視（次の更新で再試行）
    } finally {
      _remoteBusy = false;
    }
  }

  /// Supabase モード: 部屋のメッセージを引き直す（チャット画面と部屋一覧で使用）
  Future<void> reloadRoomMessages(String roomId) async {
    if (!AppConfig.useSupabase) return;
    try {
      final messages = await supabaseData.fetchMessages(roomId);
      _messages[roomId] = messages;
      notifyListeners();
    } catch (_) {
      // 無視
    }
  }
  void updateProfile({
    required String nickname,
    required String decade,
    required String gender,
    required String iconCategoryId,
    required List<String> interestIds,
    required String bio,
    String? iconImagePath,
    String? websiteUrl,
    String? snsNote,
    String? phone,
    String? storeType,
  }) {
    final old = me!;
    if (old is BusinessUser) {
      me = BusinessUser(
        id: old.id,
        nickname: nickname,
        decade: decade,
        gender: gender,
        iconCategoryId: iconCategoryId,
        interestIds: interestIds,
        bio: bio,
        lat: old.lat,
        lng: old.lng,
        storeType: storeType ?? old.storeType,
        iconImagePath: _pickIcon(old.iconImagePath, iconImagePath),
        websiteUrl: websiteUrl ?? old.websiteUrl,
        snsNote: snsNote ?? old.snsNote,
        phone: phone ?? old.phone,
      );
    } else {
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
        iconImagePath: _pickIcon(old.iconImagePath, iconImagePath),
        websiteUrl: websiteUrl ?? old.websiteUrl,
        snsNote: snsNote ?? old.snsNote,
        phone: phone ?? old.phone,
      );
    }
    _users[me!.id] = me!;
    notifyListeners();
  }

  String? _pickIcon(String? current, String? incoming) {
    if (incoming == null) return current; // 変更なし
    return incoming; // '' は解除、パスは新画像
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

  Future<Recruitment> createRecruitment({
    required String genreId,
    required String title,
    required String body,
    required String meetup,
    required int capacity,
    required int expiryHours,
  }) async {
    if (_remote) {
      final rec = await supabaseData.createRecruitment(
        genreId: genreId,
        title: title,
        body: body,
        meetup: meetup,
        capacity: capacity,
        expiryHours: expiryHours,
      );
      _recruitments.insert(0, rec);
      notifyListeners();
      return rec;
    }
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
    if (_remote) {
      unawaited(supabaseData.insertApplication(recruitmentId, message));
      return; // 本物のホストがアプリで承認する（自動承認なし）
    }
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
    if (_remote) {
      unawaited(
          supabaseData.setApplicationStatus(applicationId, JoinStatus.declined));
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
        body: '${_users[app.applicantId]?.nickname ?? '新しい参加者'}'
            ' さんが参加しました。',
        isSystem: true);
    unreadByRoom[room.id] = (unreadByRoom[room.id] ?? 0) + 1;
    notifyListeners();

    if (_remote) {
      // 実書き込み: ステータス・メンバー・部屋・システムメッセージ
      unawaited(() async {
        try {
          await supabaseData.setApplicationStatus(
              app.id, JoinStatus.accepted);
          await supabaseData.setRecruitmentMembers(
              updated.id, updated.memberIds);
          final dbRoom = await supabaseData.ensureGroupRoom(
              updated.id, updated.hostId);
          await supabaseData.addRoomMember(dbRoom.id, app.applicantId);
          await supabaseData.postMessage(dbRoom.id,
              '${_users[app.applicantId]?.nickname ?? '新しい参加者'}'
              ' さんが参加しました。',
              isSystem: true);
        } catch (_) {
          // 無視（次回の同期で回復）
        }
      }());
      return;
    }

    // デモ用: 参加者がひとこと挨拶する（モックのみ）
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
    if (_remote) {
      unawaited(supabaseData.markRoomRead(roomId));
    }
    notifyListeners();
  }

  /// 特定ユーザーとの DM ルームを取得（なければ作る）
  Future<ChatRoom> getOrCreateDm(String otherUserId) async {
    for (final room in _rooms) {
      if (room.isDm &&
          room.memberIds.contains(me!.id) &&
          room.memberIds.contains(otherUserId)) {
        return room;
      }
    }
    if (_remote) {
      final roomId = await supabaseData.getOrCreateDm(otherUserId);
      final room = ChatRoom(
        id: roomId,
        recruitmentId: '',
        memberIds: [me!.id, otherUserId],
        createdAt: _now(),
        type: 'dm',
      );
      _rooms.insert(0, room);
      _messages.putIfAbsent(room.id, () => []);
      notifyListeners();
      return room;
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
    if (_remote) {
      unawaited(supabaseData.postMessage(roomId, body));
      return;
    }
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
