import 'package:flutter/material.dart';
import '../sync_service.dart';

class SyncBanner extends StatelessWidget {
  final SyncService syncService;

  const SyncBanner({super.key, required this.syncService});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncState>(
      valueListenable: syncService.syncState,
      builder: (context, state, child) {
        Color bgColor;
        String text;
        IconData icon;

        switch (state) {
          case SyncState.offline:
            bgColor = Colors.red.shade600;
            text = 'Offline - Saved Locally';
            icon = Icons.cloud_off;
            break;
          case SyncState.syncing:
            bgColor = Colors.orange.shade600;
            text = 'Syncing...';
            icon = Icons.sync;
            break;
          case SyncState.synced:
            bgColor = Colors.green.shade600;
            text = 'Synced';
            icon = Icons.cloud_done;
            break;
          case SyncState.error:
            bgColor = Colors.red.shade900;
            text = 'Sync Error';
            icon = Icons.error_outline;
            break;
        }

        // Animated container makes the color changes smooth
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          color: bgColor,
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 12),
              const SizedBox(width: 6),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 11, 
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}