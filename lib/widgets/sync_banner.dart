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
        // 1. Check if we should hide the banner
        final isSynced = state == SyncState.synced;

        Color bgColor = Colors.green.shade600; // Fallback
        String text = '';
        IconData icon = Icons.cloud_done;

        // 2. Set up your custom UI variables (Only needed if NOT synced)
        if (!isSynced) {
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
            case SyncState.error:
              bgColor = Colors.red.shade900;
              text = 'Sync Error';
              icon = Icons.error_outline;
              break;
            default:
              break;
          }
        }

        // 3. Wrap your beautiful AnimatedContainer inside AnimatedSize!
        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: isSynced
              ? const SizedBox.shrink() // Hides perfectly with 0 height when synced
              : AnimatedContainer(      // Your original smooth color transition UI
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
                ),
        );
      },
    );
  }
}