import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/app_state.dart';
import 'store_sheet.dart';

/// 近くの店を地図で見る画面。
/// flutter_map + OpenStreetMap タイル（APIキー不要）で表示し、
/// Google マップへの外部連携は store_sheet.dart の openInGoogleMaps から行う。
class MapScreen extends StatelessWidget {
  const MapScreen({super.key, this.highlightStoreId});

  final String? highlightStoreId;

  @override
  Widget build(BuildContext context) {
    final me = appState.me!;
    final stores = appState.businessUsers;
    LatLng? initial;
    for (final s in stores) {
      if (s.id == highlightStoreId) {
        initial = LatLng(s.lat, s.lng);
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('近くの店マップ')),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: initial ?? LatLng(me.lat, me.lng),
          initialZoom: 14,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.meshitomo.meshitomo',
          ),
          MarkerLayer(
            markers: [
              // 自分（現在地）: 青丸
              Marker(
                point: LatLng(me.lat, me.lng),
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
              // 近くの店: オレンジのピン（タップで店舗シート）
              for (final s in stores)
                Marker(
                  point: LatLng(s.lat, s.lng),
                  width: 44,
                  height: 44,
                  child: InkWell(
                    onTap: () => showStoreSheet(context, s),
                    child: Icon(
                      Icons.location_on,
                      size: 44,
                      color: s.id == highlightStoreId
                          ? Colors.deepOrange
                          : Colors.orange,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
