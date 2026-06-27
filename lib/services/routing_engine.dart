import 'package:isar/isar.dart';
import '../models/database_models.dart';

class RoutingEngine {
  final Isar isar;

  RoutingEngine(this.isar);

  /// Call this when the user finishes shopping or leaves a store's geofence.
  /// Passes the shop name and the list of item names they just bought (in the exact order they checked them off!).
  Future<void> learnStoreLayout(String shopName, List<String> checkedItemNames) async {
    if (checkedItemNames.isEmpty) return;

    // 1. Fetch the master products for the checked items
    final masters = await isar.masterProducts.filter()
        .anyOf(checkedItemNames, (q, String name) => q.nameEqualTo(name))
        .findAll();

    // 2. Extract the sequence of ZONES visited, removing consecutive duplicates.
    // Example: [Dairy, Dairy, Produce, Meat] -> [Dairy, Produce, Meat]
    List<ItemCategory> visitedZones = [];
    for (var itemName in checkedItemNames) {
      final master = masters.firstWhere((m) => m.name == itemName, orElse: () => MasterProduct());
      if (master.category != ItemCategory.unmapped) {
        if (visitedZones.isEmpty || visitedZones.last != master.category) {
          visitedZones.add(master.category);
        }
      }
    }

    if (visitedZones.isEmpty) return;

    // 3. Load the Store from Isar
    final shop = await isar.userShops.where().nameEqualTo(shopName).findFirst();
    if (shop == null) return;

    // 4. Update the Zone Aisle Orders using Exponential Moving Average (EMA)
    await isar.writeTxn(() async {
      List<ZonePosition> currentLayout = List.from(shop.zoneLayout);

      for (int i = 0; i < visitedZones.length; i++) {
        final category = visitedZones[i];
        final double currentPosInSequence = (i + 1).toDouble();

        int existingIndex = currentLayout.indexWhere((z) => z.category == category);
        
        if (existingIndex != -1) {
          // EMA Math: 30% new trip data, 70% historical consensus
          // This ensures a single weird shopping trip doesn't ruin the route.
          double oldOrder = currentLayout[existingIndex].aisleOrder;
          currentLayout[existingIndex].aisleOrder = (0.3 * currentPosInSequence) + (0.7 * oldOrder);
        } else {
          // First time mapping this zone in this store!
          currentLayout.add(ZonePosition()
            ..category = category
            ..aisleOrder = currentPosInSequence
          );
        }
      }

      shop.zoneLayout = currentLayout;
      shop.lastModified = DateTime.now().toUtc(); // Flag for sync engine
      await isar.userShops.put(shop);
    });
  }
}