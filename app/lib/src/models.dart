import 'package:flutter/material.dart';

/// 募集ジャンル
class Genre {
  final String id;
  final String label;
  final IconData icon;
  const Genre(this.id, this.label, this.icon);
}

const List<Genre> genres = [
  Genre('meshi', 'ご飯', Icons.dinner_dining),
  Genre('nomi', '飲み', Icons.local_bar),
  Genre('cafe', 'カフェ', Icons.local_cafe),
];

Genre genreById(String id) => genres.firstWhere((g) => g.id == id);

/// 興味カテゴリ（本開発ではマスタデータ化してアプリ再リリースなしで追加できるようにする）
class InterestCategory {
  final String id;
  final String label;
  final IconData icon;
  const InterestCategory(this.id, this.label, this.icon);
}

const List<InterestCategory> interestCategories = [
  InterestCategory('izakaya', '居酒屋', Icons.local_bar),
  InterestCategory('yakiniku', '焼肉', Icons.outdoor_grill),
  InterestCategory('ramen', 'ラーメン', Icons.ramen_dining),
  InterestCategory('cafe', 'カフェ', Icons.local_cafe),
  InterestCategory('sweets', 'スイーツ', Icons.cake),
  InterestCategory('sushi', '寿司・魚介', Icons.set_meal),
  InterestCategory('pasta', 'パスタ・イタリアン', Icons.dinner_dining),
  InterestCategory('pizza', 'ピザ', Icons.local_pizza),
  InterestCategory('burger', 'ハンバーガー', Icons.lunch_dining),
  InterestCategory('spicy', '激辛', Icons.local_fire_department),
  InterestCategory('ethnic', 'エスニック・アジア', Icons.rice_bowl),
  InterestCategory('brunch', '朝食・ブランチ', Icons.brunch_dining),
];

InterestCategory categoryById(String id) =>
    interestCategories.firstWhere((c) => c.id == id);

/// プロトタイプ用のモック現在地（本開発では端末の GPS + geohash に置き換える）
class MockLocation {
  final String id;
  final String name;
  final double lat;
  final double lng;
  const MockLocation(this.id, this.name, this.lat, this.lng);
}

const List<MockLocation> mockLocations = [
  MockLocation('tokyo', '東京駅', 35.6812, 139.7671),
  MockLocation('yurakucho', '有楽町', 35.6748, 139.7629),
  MockLocation('akiba', '秋葉原', 35.7023, 139.7745),
  MockLocation('shibuya', '渋谷', 35.6580, 139.7016),
  MockLocation('shinjuku', '新宿', 35.6896, 139.7006),
  MockLocation('shinagawa', '品川', 35.6285, 139.7394),
];

class AppUser {
  final String id;
  final String nickname;
  final String decade; // 例: '20代'
  final String gender; // 'male' | 'female' | 'undisclosed'
  final String iconCategoryId; // 趣味アイコン（顔画像は禁止）
  final String? iconImagePath; // 端末内に保存した投稿アイコン画像（あれば優先表示）
  final List<String> interestIds;
  final String bio;
  final double lat;
  final double lng;

  const AppUser({
    required this.id,
    required this.nickname,
    required this.decade,
    required this.gender,
    required this.iconCategoryId,
    required this.interestIds,
    required this.bio,
    required this.lat,
    required this.lng,
    this.iconImagePath,
  });

  String get genderLabel => const {'male': '男性', 'female': '女性'}.containsKey(gender)
      ? const {'male': '男性', 'female': '女性'}[gender]!
      : '非公開';

  bool get isBusiness => false;
}

/// ビジネスユーザー（v1.5 の完成形に向けたプレビュー。店舗情報を持つ）
class BusinessUser extends AppUser {
  final String storeType; // 例: '居酒屋'

  const BusinessUser({
    required super.id,
    required super.nickname,
    required super.decade,
    required super.gender,
    required super.iconCategoryId,
    required super.interestIds,
    required super.bio,
    required super.lat,
    required super.lng,
    required this.storeType,
  });

  @override
  bool get isBusiness => true;
}

enum RecStatus { active, fulfilled, expired, cancelled }

class Recruitment {
  final String id;
  final String hostId;
  final String genreId;
  final String title;
  final String body;
  final String meetup;
  final int capacity;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> memberIds; // host を含む

  const Recruitment({
    required this.id,
    required this.hostId,
    required this.genreId,
    required this.title,
    required this.body,
    required this.meetup,
    required this.capacity,
    required this.createdAt,
    required this.expiresAt,
    required this.memberIds,
  });

  bool get isFull => memberIds.length >= capacity;

  bool isActiveAt(DateTime now) =>
      now.isBefore(expiresAt) && !isFull && memberIds.isNotEmpty;

  int get remainingSlots => capacity - memberIds.length;

  RecStatus statusAt(DateTime now) {
    if (isFull) return RecStatus.fulfilled;
    if (!now.isBefore(expiresAt)) return RecStatus.expired;
    return RecStatus.active;
  }
}

enum JoinStatus { pending, accepted, declined }

class JoinApplication {
  final String id;
  final String recruitmentId;
  final String applicantId;
  final String message;
  JoinStatus status;
  final DateTime createdAt;

  JoinApplication({
    required this.id,
    required this.recruitmentId,
    required this.applicantId,
    required this.message,
    required this.status,
    required this.createdAt,
  });
}

class ChatRoom {
  final String id;
  final String recruitmentId; // DM の場合は空文字
  final List<String> memberIds;
  final DateTime createdAt;
  final String type; // 'group'（募集から生成） | 'dm'（1:1）

  ChatRoom({
    required this.id,
    required this.recruitmentId,
    required this.memberIds,
    required this.createdAt,
    this.type = 'group',
  });

  bool get isDm => type == 'dm';
}

class ChatMessage {
  final String id;
  final String roomId;
  final String senderId; // system の場合 'system'
  final String body;
  final DateTime sentAt;
  final bool isSystem;

  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.body,
    required this.sentAt,
    this.isSystem = false,
  });
}
