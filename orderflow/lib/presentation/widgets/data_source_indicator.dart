import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/websocket_datasource.dart';

/// Data source status indicator widget
Widget buildDataSourceIndicator(DataSourceStatus status) {
  Color color;
  String text;
  IconData icon;

  if (status.isConnected) {
    if (status.type == DataSourceType.mstock) {
      color = AppTheme.bullColor;
      text = 'm.Stock';
      icon = Icons.cloud_done;
    } else if (status.type == DataSourceType.zerodha) {
      color = Colors.orange;
      text = 'Zerodha';
      icon = Icons.cloud_done;
    } else if (status.type == DataSourceType.kotak) {
      color = Colors.redAccent;
      text = 'Kotak Neo';
      icon = Icons.cloud_done;
    } else if (status.type == DataSourceType.simulated) {
      color = Colors.orange;
      text = 'Simulated';
      icon = Icons.warning_amber;
    } else {
      color = AppTheme.primaryCyan;
      text = 'Connected';
      icon = Icons.cloud_done;
    }
  } else {
    color = Colors.grey;
    text = 'No Data';
    icon = Icons.cloud_off;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
