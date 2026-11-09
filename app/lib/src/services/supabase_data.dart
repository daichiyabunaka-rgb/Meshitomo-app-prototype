import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../util/geohash.dart';

/// Supabase モードでのデータアクセス層。
/// AppState はモック（インメモリ）とこのクラスを AppConfig.useSupabase で切り替える。
/// 位置は geohash のみを扱い、生の緯度経度は DB に保存しない
/// （仕様書 6 章 位置情報プライバシー）。
class SupabaseData {
  SupabaseClient get _c => Supabase.instance.client;

  String get _myId => _c.auth.currentUser!.id;

  // ---------------------------------------------------------- profiles

  Future<void> updateMyLocation(double lat, double lng) async {
    await _c.from('profiles').update({
      'location_geohash': geohashEncode(lat, lng, precision: 6),
      'online': true,
    }).eq('id', _myId);
  }

  /// 近くの一般ユーザー / 店舗（geohash プレフィックス、近百人）
  Future<List<AppUser>> fetchNearbyUsers(AppUser me) async {
    final rows = await _c
        .from('profiles')
        .select()
        .neq('id', _myId)
        .not('location_geohash', 'is', null)
        .limit(100);
    final users = <AppUser>[];
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      try {
        users.add(_rowToUser(row));
      } catch (_) {
        // 壊れた行は読み飛ばす
      }
    }
    // 近傍（geohash 先頭4桁一致 = 約20km四方）だけ残す
    final myPrefix = geohashEncode(me.lat, me.lng, precision: 4);
    return users
        .where((u) =>
            u.nickname.isNotEmpty &&
            (geohashEncode(u.lat, u.lng, precision: 4) == myPrefix))
        .toList();
  }

  AppUser _rowToUser(Map<String, dynamic> row) {
    final gh = row['location_geohash'] as String?;
    final (lat, lng) =
        gh == null ? (35.6812, 139.7671) : geohashDecode(gh);
    final isBusiness = row['role'] == 'business';
    if (isBusiness) {
      return BusinessUser(
        id: row['id'] as String,
        nickname: (row['nickname'] as String?) ?? '店舗',
        decade: (row['birth_decade'] as String?) ?? '経営者',
        gender: row['gender'] as String? ?? 'undisclosed',
        iconCategoryId: row['icon_category_id'] as String? ?? 'izakaya',
        interestIds:
            ((row['interest_ids'] as List?) ?? const []).cast<String>(),
        bio: (row['bio'] as String?) ?? '',
        lat: lat,
        lng: lng,
        storeType: (row['store_type'] as String?) ?? '店舗',
        websiteUrl: row['website_url'] as String?,
        snsNote: row['sns_note'] as String?,
        phone: row['phone'] as String?,
      );
    }
    return AppUser(
      id: row['id'] as String,
      nickname: (row['nickname'] as String?) ?? '名無し',
      decade: (row['birth_decade'] as String?) ?? '非公開',
      gender: row['gender'] as String? ?? 'undisclosed',
      iconCategoryId: row['icon_category_id'] as String? ?? 'ramen',
      interestIds: ((row['interest_ids'] as List?) ?? const []).cast<String>(),
      bio: (row['bio'] as String?) ?? '',
      lat: lat,
      lng: lng,
      websiteUrl: row['website_url'] as String?,
      snsNote: row['sns_note'] as String?,
      phone: row['phone'] as String?,
    );
  }

  // ---------------------------------------------------------- recruitments

  Future<Recruitment> createRecruitment({
    required String genreId,
    required String title,
    required String body,
    required String meetup,
    required int capacity,
    required int expiryHours,
  }) async {
    final now = DateTime.now().toUtc();
    final rows = await _c.from('recruitments').insert({
      'host_id': _myId,
      'genre_id': genreId,
      'title': title,
      'body': body,
      'meetup': meetup,
      'capacity': capacity,
      'expires_at': now.add(Duration(hours: expiryHours)).toIso8601String(),
      'status': 'active',
    }).select();
    final row = (rows as List).first as Map<String, dynamic>;
    return Recruitment(
      id: row['id'] as String,
      hostId: _myId,
      genreId: genreId,
      title: title,
      body: body,
      meetup: meetup,
      capacity: capacity,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      expiresAt: DateTime.parse(row['expires_at'] as String).toLocal(),
      memberIds: [row['host_id'] as String],
    );
  }

  /// アクティブな募集（新着順、最大50件。ホストのプロフィールも一緒に返す）
  Future<(List<Recruitment>, List<AppUser>)> fetchActiveRecruitments(
      AppUser me) async {
    final rows = await _c
        .from('recruitments')
        .select()
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .limit(50);
    final recs = <Recruitment>[];
    final hostIds = <String>{};
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final expiresAt = DateTime.parse(row['expires_at'] as String).toLocal();
      if (expiresAt.isBefore(DateTime.now())) continue;
      final memberIds =
          ((row['member_ids'] as List?) ?? const []).cast<String>().toList();
      final hostId = row['host_id'] as String;
      hostIds.add(hostId);
      recs.add(Recruitment(
        id: row['id'] as String,
        hostId: hostId,
        genreId: row['genre_id'] as String,
        title: row['title'] as String,
        body: (row['body'] as String?) ?? '',
        meetup: (row['meetup'] as String?) ?? '',
        capacity: (row['capacity'] as int?) ?? 3,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        expiresAt: expiresAt,
        memberIds: memberIds.contains(hostId) ? memberIds : [hostId, ...memberIds],
      ));
    }
    if (hostIds.isEmpty) return (recs, <AppUser>[]);
    final profileRows =
        await _c.from('profiles').select().inFilter('id', hostIds.toList());
    final hosts = (profileRows as List)
        .map((r) => _rowToUser(r as Map<String, dynamic>))
        .toList();
    return (recs, hosts);
  }

  Future<void> setRecruitmentMembers(
      String recruitmentId, List<String> memberIds) async {
    await _c.from('recruitments').update({
      'member_ids': memberIds,
      'status': 'active', // 満員時はクライアントで fulfilled 判定する
    }).eq('id', recruitmentId);
  }

  // ---------------------------------------------------------- applications

  Future<void> insertApplication(String recruitmentId, String message) async {
    await _c.from('join_applications').upsert({
      'recruitment_id': recruitmentId,
      'applicant_id': _myId,
      'message': message,
      'status': 'pending',
    });
  }

  /// 主催者として受けた応募 + 応募者のプロフィール。
  /// （host の募集に限る。RLS により自分の募集への応募のみ見える）
  Future<(List<JoinApplication>, List<AppUser>)> fetchHostApplications(
      List<Recruitment> myRecruitments) async {
    if (myRecruitments.isEmpty) {
      return (<JoinApplication>[], <AppUser>[]);
    }
    final ids = myRecruitments.map((r) => r.id).toList();
    final rows = await _c
        .from('join_applications')
        .select()
        .inFilter('recruitment_id', ids)
        .order('created_at');
    final apps = <JoinApplication>[];
    final applicants = <String>{};
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      apps.add(_rowToApplication(row));
      applicants.add(row['applicant_id'] as String);
    }
    if (applicants.isEmpty) return (apps, const <AppUser>[]);
    final profileRows =
        await _c.from('profiles').select().inFilter('id', applicants.toList());
    final users = (profileRows as List)
        .map((r) => _rowToUser(r as Map<String, dynamic>))
        .toList();
    return (apps, users);
  }

  /// 自分が応募した側のステータス
  Future<List<JoinApplication>> fetchMyApplications() async {
    final rows = await _c
        .from('join_applications')
        .select()
        .eq('applicant_id', _myId)
        .order('created_at');
    return (rows as List)
        .map((r) => _rowToApplication(r as Map<String, dynamic>))
        .toList();
  }

  JoinApplication _rowToApplication(Map<String, dynamic> row) {
    return JoinApplication(
      id: row['id'] as String,
      recruitmentId: row['recruitment_id'] as String,
      applicantId: row['applicant_id'] as String,
      message: (row['message'] as String?) ?? '',
      status: switch (row['status'] as String?) {
        'accepted' => JoinStatus.accepted,
        'declined' => JoinStatus.declined,
        _ => JoinStatus.pending,
      },
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }

  Future<void> setApplicationStatus(String applicationId, JoinStatus status) async {
    await _c.from('join_applications').update({
      'status': status == JoinStatus.accepted
          ? 'accepted'
          : status == JoinStatus.declined
              ? 'declined'
              : 'pending',
    }).eq('id', applicationId);
  }

  // ---------------------------------------------------------- rooms / DM

  Future<ChatRoom> ensureGroupRoom(String recruitmentId, String hostId) async {
    final existingRows =
        (await _c.from('chat_rooms').select().eq('recruitment_id', recruitmentId).limit(1))
            as List;
    if (existingRows.isNotEmpty) {
      final row = Map<String, dynamic>.from(existingRows.first as Map);
      final members = await _roomMembers(row['id'] as String);
      return ChatRoom(
        id: row['id'] as String,
        recruitmentId: recruitmentId,
        memberIds: members,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );
    }
    final created = await _c.from('chat_rooms').insert({
      'recruitment_id': recruitmentId,
      'type': 'group',
    }).select();
    final row = (created as List).first as Map<String, dynamic>;
    final roomId = row['id'] as String;
    await _c.from('chat_room_members').upsert([
      {'room_id': roomId, 'user_id': hostId},
      {'room_id': roomId, 'user_id': _myId},
    ]);
    return ChatRoom(
      id: roomId,
      recruitmentId: recruitmentId,
      memberIds: [hostId, _myId],
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }

  Future<void> addRoomMember(String roomId, String userId) async {
    await _c.from('chat_room_members').upsert({
      'room_id': roomId,
      'user_id': userId,
    });
  }

  Future<List<String>> _roomMembers(String roomId) async {
    final rows =
        await _c.from('chat_room_members').select('user_id').eq('room_id', roomId);
    return (rows as List)
        .map((r) => (r as Map<String, dynamic>)['user_id'] as String)
        .toList();
  }

  /// DM の部屋を取得（なければ作成）。戻り値は roomId
  Future<String> getOrCreateDm(String otherUserId) async {
    final res = await _c.rpc('get_or_create_dm', params: {
      'p_other_user': otherUserId,
    });
    return res as String;
  }

  Future<void> postMessage(String roomId, String body,
      {bool isSystem = false}) async {
    await _c.from('chat_messages').insert({
      'room_id': roomId,
      'sender_id': _myId,
      'body': body,
      'is_system': isSystem,
    });
  }

  Future<List<ChatMessage>> fetchMessages(String roomId) async {
    final rows = await _c
        .from('chat_messages')
        .select()
        .eq('room_id', roomId)
        .order('sent_at')
        .limit(200);
    return (rows as List).map((r) {
      final row = r as Map<String, dynamic>;
      return ChatMessage(
        id: row['id'] as String,
        roomId: roomId,
        senderId: row['sender_id'] as String,
        body: row['body'] as String,
        sentAt: DateTime.parse(row['sent_at'] as String).toLocal(),
        isSystem: (row['is_system'] as bool?) ?? false,
      );
    }).toList();
  }

  Future<void> markRoomRead(String roomId) async {
    await _c.from('chat_room_members')
        .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('room_id', roomId)
        .eq('user_id', _myId);
  }

  /// 自分が参加している部屋（メンバー一覧も取得）
  Future<List<ChatRoom>> fetchMyRooms() async {
    final rows = await _c
        .from('chat_room_members')
        .select('room_id, chat_rooms!inner(id, recruitment_id, type, created_at)')
        .eq('user_id', _myId)
        .order('joined_at', ascending: false)
        .limit(20);
    final rooms = <ChatRoom>[];
    final roomIds = <String>[];
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final room = r['chat_rooms'] as Map<String, dynamic>;
      final id = room['id'] as String;
      roomIds.add(id);
      rooms.add(ChatRoom(
        id: id,
        recruitmentId: (room['recruitment_id'] as String?) ?? '',
        memberIds: const [],
        createdAt: DateTime.parse(room['created_at'] as String).toLocal(),
        type: (room['type'] as String?) ?? 'group',
      ));
    }
    if (roomIds.isEmpty) return rooms;
    // 全メンバーを一括取得して rooms に反映
    final memberRows = await _c
        .from('chat_room_members')
        .select('room_id, user_id')
        .inFilter('room_id', roomIds);
    final membersByRoom = <String, List<String>>{};
    for (final r in (memberRows as List).cast<Map<String, dynamic>>()) {
      membersByRoom
          .putIfAbsent(r['room_id'] as String, () => [])
          .add(r['user_id'] as String);
    }
    return rooms
        .map((room) => ChatRoom(
              id: room.id,
              recruitmentId: room.recruitmentId,
              memberIds:
                  membersByRoom[room.id] ?? [_myId],
              createdAt: room.createdAt,
              type: room.type,
            ))
        .toList();
  }
}

/// グローバルインスタンス
final SupabaseData supabaseData = SupabaseData();
