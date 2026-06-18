import 'package:flutter/material.dart';
import '../models/database_models.dart';
import '../services/location_routing_service.dart';

/// A non-intrusive banner that appears when a geofence or Places result is detected.
/// For a *known* shop: shows Confirm / Change.
/// For a *new* shop (from Places API): shows Confirm + "Add to My Shops" / Change.
class StoreDetectionBanner extends StatelessWidget {
  final DetectedShop detectedShop;
  final List<UserShop> allShops;
  final VoidCallback onConfirm;
  final ValueChanged<UserShop> onOverride;
  final VoidCallback onDismiss;

  const StoreDetectionBanner({
    super.key,
    required this.detectedShop,
    required this.allShops,
    required this.onConfirm,
    required this.onOverride,
    required this.onDismiss,
  });

  void _showStorePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Select your store',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ...allShops.map((shop) => ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade50,
                child: Icon(Icons.storefront, color: Colors.blue.shade700, size: 20),
              ),
              title: Text(shop.name),
              trailing: shop.name == detectedShop.name
                  ? Icon(Icons.check_circle, color: Colors.blue.shade700)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                onOverride(shop);
              },
            )),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey.shade100,
                child: Icon(Icons.close, color: Colors.grey.shade600, size: 20),
              ),
              title: const Text('I\'m not in a store'),
              onTap: () {
                Navigator.pop(ctx);
                onDismiss();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = detectedShop.isNew;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: Material(
        color: isNew ? Colors.deepPurple.shade600 : Colors.blue.shade700,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isNew ? Icons.explore : Icons.location_on,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),

                // Label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isNew ? 'Nearby store detected:' : 'Looks like you\'re at:',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      Text(
                        detectedShop.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isNew)
                        const Text(
                          'Not in your shops yet',
                          style: TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                    ],
                  ),
                ),

                // Action buttons
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: onConfirm,
                  // For new stores, make it clear we'll save them
                  child: Text(
                    isNew ? 'Add + Shop ✓' : 'Yes! ✓',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  onPressed: () => _showStorePicker(context),
                  child: const Text('Change', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
