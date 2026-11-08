import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';

/// 趣味アイコンのアバター（顔画像は使わない設計 FR-1-3）
Widget userAvatar(String userId, {double size = 44, double iconScale = 0.5}) {
  final user = appState.userById(userId);
  final cat = categoryById(user.iconCategoryId);
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.deepOrange.shade50,
    ),
    child: Icon(
      cat.icon,
      size: size * iconScale,
      color: Colors.deepOrange.shade800,
    ),
  );
}

Widget genreChip(String genreId) {
  final g = genreById(genreId);
  return Container(
    padding: const.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.orange.shade200),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(g.icon, size: 14, color: Colors.orange.shade800),
        const SizedBox(width: 4),
        Text(g.label, style: TextStyle(color: Colors.orange.shade900, fontSize: 12)),
      ],
    ),
  );
}

Widget interestLabel(InterestCategory c) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(c.icon, size: 14, color: Colors.grey.shade700),
        const SizedBox(width: 4),
        Text(c.label, style: TextStyle(color: Colors.grey.shade800, fontSize: 12)),
      ],
    ),
  );
}
