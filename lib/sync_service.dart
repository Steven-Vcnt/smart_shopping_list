import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/database_models.dart';

enum SyncState { offline, syncing, synced, error }

class SyncService {
  final Isar isar;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  final ValueNotifier<SyncState> syncState = ValueNotifier(SyncState.offline);
  
  StreamSubscription? _connectivitySub;
  StreamSubscription? _authSub;

  SyncService(this.isar) {
    _initListeners();
  }

  void _initListeners() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (!results.contains(ConnectivityResult.none)) syncNow();
    });
    
    _authSub = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) syncNow();
    });
  }

  Future<void> syncNow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("Sync Aborted: User null.");
      return;
    }

    try {
      syncState.value = SyncState.syncing;
      
      // 1. Sync Lists (Private User Data)
      await _pullCloudChangesToLocal();
      await _pushLocalChangesToCloud();

      // 2. Sync Master Products (The Hive Mind Taxonomy)
      await _pullMasterProducts();
      await _pushMasterProducts();

      // 3. Sync Store Layouts (Crowdsourced Routing)
      await _pullShops();
      await _pushShops();

      syncState.value = SyncState.synced;
      debugPrint("✅ Sync Completed Successfully");
    } catch (e) {
      debugPrint('🔴 Sync Error: $e');
      syncState.value = SyncState.error;
    }
  }

  // --- 1. LIST SYNC ---
  Future<void> _pullCloudChangesToLocal() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    final snapshot = await _firestore.collection('shared_lists')
        .where(Filter.or(
          Filter('ownerEmail', isEqualTo: user.email),
          Filter('sharedWith', arrayContains: user.email),
        )).get();

    final localSyncedLists = await isar.smartLists.filter().firebaseIdIsNotNull().findAll();
    final activeCloudIds = snapshot.docs.map((doc) => doc.id).toSet();
    
    List<int> listIdsToDelete = [];
    List<SmartList> listsToUpdate = [];

    for (var localList in localSyncedLists) {
      if (!activeCloudIds.contains(localList.firebaseId)) listIdsToDelete.add(localList.id);
    }

    for (var doc in snapshot.docs) {
      final cloudData = doc.data();
      final cloudModified = DateTime.parse(cloudData['lastModified']).toUtc();
      final localList = localSyncedLists.firstWhere((l) => l.firebaseId == doc.id, orElse: () => SmartList());

      final List<dynamic> itemsData = cloudData['items'] ?? [];
      final cloudItems = itemsData.map((m) => ListItem()
        ..name = m['name']
        ..isChecked = m['isChecked'] ?? false
        ..emoji = m['emoji']
        ..quantity = (m['quantity'] as num?)?.toDouble()
        ..defaultShops = List<String>.from(m['defaultShops'] ?? [])
      ).toList();

      if (localList.firebaseId == null) {
        listsToUpdate.add(SmartList()
          ..firebaseId = doc.id
          ..name = cloudData['name']
          ..type = ListType.values.firstWhere((e) => e.name == cloudData['type'], orElse: () => ListType.restock)
          ..items = cloudItems
          ..lastModified = cloudModified
          ..ownerEmail = cloudData['ownerEmail']
          ..ownerUid = cloudData['ownerUid']
          ..sharedWith = List<String>.from(cloudData['sharedWith'] ?? [])
          ..lastSynced = DateTime.now().toUtc());
      } else {
        localList.items = cloudItems;
        localList.lastModified = cloudModified;
        localList.lastSynced = DateTime.now().toUtc();
        listsToUpdate.add(localList);
      }
    }

    await isar.writeTxn(() async {
      await isar.smartLists.deleteAll(listIdsToDelete);
      await isar.smartLists.putAll(listsToUpdate);
    });
  }

  Future<void> _pushLocalChangesToCloud() async {
    final localLists = await isar.smartLists.where().findAll();
    final batch = _firestore.batch();
    final user = FirebaseAuth.instance.currentUser;

    for (var list in localLists) {
      if (list.firebaseId == null || (list.lastSynced == null || list.lastModified.isAfter(list.lastSynced!))) {
        final docRef = list.firebaseId == null ? _firestore.collection('shared_lists').doc() : _firestore.collection('shared_lists').doc(list.firebaseId);
        list.firebaseId = docRef.id;

        batch.set(docRef, {
          'name': list.name,
          'type': list.type.name,
          'lastModified': list.lastModified.toUtc().toIso8601String(),
          'ownerEmail': list.ownerEmail ?? user?.email,
          'ownerUid': list.ownerUid ?? user?.uid,
          'sharedWith': list.sharedWith,
          'items': list.items.map((i) => {'name': i.name, 'isChecked': i.isChecked, 'emoji': i.emoji, 'quantity': i.quantity, 'defaultShops': i.defaultShops}).toList(),
        }, SetOptions(merge: true));
        
        list.lastSynced = DateTime.now().toUtc();
        await isar.writeTxn(() => isar.smartLists.put(list));
      }
    }
    await batch.commit();
  }

  // --- 2. MASTERBASE SYNC ---
  Future<void> _pullMasterProducts() async {
    final snapshot = await _firestore.collection('global_master_products').get();
    List<MasterProduct> toUpdate = [];

    for (var doc in snapshot.docs) {
      final data = doc.data();
      var master = await isar.masterProducts.where().nameEqualTo(data['name']).findFirst() 
                ?? MasterProduct()..name = data['name'];

      master.firebaseId = doc.id;
      master.emoji = data['emoji'] ?? '🛒';
      master.category = ItemCategory.values.firstWhere((e) => e.name == data['category'], orElse: () => ItemCategory.unmapped);
      
      toUpdate.add(master);
    }
    await isar.writeTxn(() async => await isar.masterProducts.putAll(toUpdate));
  }

  Future<void> _pushMasterProducts() async {
    final localMasters = await isar.masterProducts.where().findAll();
    final batch = _firestore.batch();
    
    for (var m in localMasters) {
      if (m.firebaseId == null) {
        final ref = _firestore.collection('global_master_products').doc();
        m.firebaseId = ref.id;
        batch.set(ref, {'name': m.name, 'emoji': m.emoji, 'category': m.category.name});
        await isar.writeTxn(() => isar.masterProducts.put(m));
      }
    }
    await batch.commit();
  }

  // --- 3. SHOP LAYOUT SYNC ---
  Future<void> _pullShops() async {
    final snapshot = await _firestore.collection('global_shop_layouts').get();
    List<UserShop> shopsToUpdate = [];

    for (var doc in snapshot.docs) {
      final data = doc.data();
      var shop = await isar.userShops.where().nameEqualTo(data['name']).findFirst() 
              ?? UserShop()..name = data['name'];

      final List<dynamic> layoutData = data['zoneLayout'] ?? [];
      shop.zoneLayout = layoutData.map((z) => ZonePosition()
        ..category = ItemCategory.values.firstWhere((e) => e.name == z['category'], orElse: () => ItemCategory.unmapped)
        ..aisleOrder = (z['aisleOrder'] as num).toDouble()
      ).toList();

      shopsToUpdate.add(shop);
    }
    await isar.writeTxn(() async => await isar.userShops.putAll(shopsToUpdate));
  }

  Future<void> _pushShops() async {
    final localShops = await isar.userShops.where().findAll();
    final batch = _firestore.batch();
    
    for (var s in localShops) {
      final ref = _firestore.collection('global_shop_layouts').doc(s.name);
      batch.set(ref, {
        'name': s.name,
        'zoneLayout': s.zoneLayout.map((z) => {'category': z.category.name, 'aisleOrder': z.aisleOrder}).toList(),
      });
    }
    await batch.commit();
  }

  void dispose() {
    _connectivitySub?.cancel();
    _authSub?.cancel(); 
    syncState.dispose();
  }
}