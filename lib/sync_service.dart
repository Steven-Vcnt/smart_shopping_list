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
      if (!results.contains(ConnectivityResult.none)) {
        syncNow();
      } else {
        syncState.value = SyncState.offline;
      }
    });
    
    _authSub = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        syncNow();
      } else {
        syncState.value = SyncState.offline; 
      }
    });

    // Don't call syncNow() immediately on boot; let the Auth Listener trigger it once it confirms a user exists.
  }

  Future<void> syncNow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("Sync Aborted: User is null. Waiting for auth state change.");
      return; 
    }

    // REMOVED the strict connectivity_plus blocker. 
    // Firestore handles offline caching automatically. It's better to let Firestore 
    // attempt the connection rather than blocking it manually.

    try {
      syncState.value = SyncState.syncing;
      
      // PULL BEFORE PUSH!
      await _pullCloudChangesToLocal();
      await _pushLocalChangesToCloud();

      syncState.value = SyncState.synced;
      debugPrint("✅ Sync Completed Successfully");
    } catch (e) {
      debugPrint('🔴 Sync Error Caught: $e');
      syncState.value = SyncState.error;
    }
  }
Future<void> _pullCloudChangesToLocal() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    try {
      final snapshot = await _firestore.collection('shared_lists')
          .where(
            Filter.or(
              Filter('ownerEmail', isEqualTo: user.email),
              Filter('sharedWith', arrayContains: user.email),
            ),
          )
          .get();

      final localSyncedLists = await isar.smartLists.filter().firebaseIdIsNotNull().findAll();
      final Set<String> activeCloudIds = snapshot.docs.map((doc) => doc.id).toSet();
      
      // We will collect all lists to delete and update, then do ONE database transaction.
      List<int> listIdsToDelete = [];
      List<SmartList> listsToUpdate = [];
      List<ListItem> allCloudItemsToLearn = []; // For batching the emoji learning

      for (var localList in localSyncedLists) {
         if (!activeCloudIds.contains(localList.firebaseId)) {
            listIdsToDelete.add(localList.id);
         }
      }

      for (var doc in snapshot.docs) {
        final cloudData = doc.data();
        if (cloudData['lastModified'] == null) continue;
        
        final cloudModified = DateTime.parse(cloudData['lastModified']).toUtc();
        
        // Find the local list IN MEMORY (Lightning fast!)
        final localListIndex = localSyncedLists.indexWhere((l) => l.firebaseId == doc.id);
        SmartList? localList = localListIndex != -1 ? localSyncedLists[localListIndex] : null;

        final List<dynamic> itemsData = cloudData['items'] ?? [];
        final cloudItems = itemsData.map((itemMap) => ListItem()
          ..name = itemMap['name']
          ..isChecked = itemMap['isChecked'] ?? false
          ..emoji = itemMap['emoji']
          ..quantity = (itemMap['quantity'] as num?)?.toDouble()
          ..defaultShops = List<String>.from(itemMap['defaultShops'] ?? [])
        ).toList();

        allCloudItemsToLearn.addAll(cloudItems); // Add to our giant batch
        
        if (localList == null) {
          final newList = SmartList()
            ..firebaseId = doc.id
            ..name = cloudData['name']
            ..type = ListType.values.firstWhere((e) => e.name == cloudData['type'], orElse: () => ListType.restock)
            ..items = cloudItems
            ..lastModified = cloudModified
            // FIX: Save the original owner and share list locally!
            ..ownerEmail = cloudData['ownerEmail']
            ..ownerUid = cloudData['ownerUid']
            ..sharedWith = List<String>.from(cloudData['sharedWith'] ?? [])
            ..lastSynced = DateTime.now().toUtc(); 

          listsToUpdate.add(newList);
        } else {
          // SMART MERGE (Union Strategy)
          
          // FIX: Ensure we constantly update our local permissions to match the cloud
          localList.ownerEmail = cloudData['ownerEmail'];
          localList.ownerUid = cloudData['ownerUid'];
          localList.sharedWith = List<String>.from(cloudData['sharedWith'] ?? []);
          
          Map<String, ListItem> mergedMap = {};
          bool rescuedCloudItems = false;

          for (var item in localList.items) {
            if (item.name != null) mergedMap[item.name!.toLowerCase()] = item;
          }

          for (var cloudItem in cloudItems) {
            if (cloudItem.name == null) continue;
            final key = cloudItem.name!.toLowerCase();

            if (mergedMap.containsKey(key)) {
              if (cloudModified.isAfter(localList.lastModified)) {
                mergedMap[key] = cloudItem;
              }
            } else {
              mergedMap[key] = cloudItem;
              rescuedCloudItems = true;
            }
          }

          localList.items = mergedMap.values.toList();

          if (rescuedCloudItems) {
            localList.lastModified = DateTime.now().toUtc();
            localList.lastSynced = null; 
          } else {
            localList.lastModified = cloudModified.isAfter(localList.lastModified) ? cloudModified : localList.lastModified;
            localList.lastSynced = DateTime.now().toUtc();
          }

          listsToUpdate.add(localList);
        }
      }

      // 1. Bulk Learn Emojis First
      if (allCloudItemsToLearn.isNotEmpty) {
        try {
          await _learnEmojisFromCloudFast(allCloudItemsToLearn);
        } catch (e) {
          debugPrint("⚠️ Warning: Failed to learn emojis: $e");
        }
      }

      // 2. Perform ONE massive, lightning-fast database transaction
      if (listIdsToDelete.isNotEmpty || listsToUpdate.isNotEmpty) {
        await isar.writeTxn(() async {
          if (listIdsToDelete.isNotEmpty) await isar.smartLists.deleteAll(listIdsToDelete);
          if (listsToUpdate.isNotEmpty) await isar.smartLists.putAll(listsToUpdate);
        });
      }

    } catch (e) {
      debugPrint("🔴 Error in _pullCloudChangesToLocal: $e");
      rethrow; 
    }
  }

  // --- PUSH: Local to Cloud ---
  Future<void> _pushLocalChangesToCloud() async {
    try {
      final localLists = await isar.smartLists.where().findAll();
      final batch = _firestore.batch();

      for (var list in localLists) {
        if (list.firebaseId == null || (list.lastSynced == null || list.lastModified.isAfter(list.lastSynced!))) {
          
          DocumentReference docRef;
          if (list.firebaseId == null) {
            docRef = _firestore.collection('shared_lists').doc(); 
            list.firebaseId = docRef.id;
          } else {
            docRef = _firestore.collection('shared_lists').doc(list.firebaseId);
          }

          final itemsJson = list.items.map((item) => {
            'name': item.name,
            'isChecked': item.isChecked,
            'emoji': item.emoji,
            'quantity': item.quantity,
            'defaultShops': item.defaultShops,
          }).toList();

          final currentUser = FirebaseAuth.instance.currentUser;

          batch.set(docRef, {
          'name': list.name,
          'type': list.type.name,
          'lastModified': list.lastModified.toUtc().toIso8601String(), 
          // FIX: Use the list's original owner, only fall back to currentUser if it's a brand new list!
          'ownerEmail': list.ownerEmail ?? currentUser?.email ?? 'anonymous',
          'ownerUid': list.ownerUid ?? currentUser?.uid ?? 'unknown',
          'sharedWith': list.sharedWith, 
          'items': itemsJson,
        }, SetOptions(merge: true));
          list.lastSynced = DateTime.now().toUtc(); 
          await isar.writeTxn(() async {
            await isar.smartLists.put(list);
          });
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint("🔴 Error in _pushLocalChangesToCloud: $e");
      rethrow;
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
    _authSub?.cancel(); 
    syncState.dispose();
  }

// --- NEW: Batch Processing for Emojis ---
  Future<void> _learnEmojisFromCloudFast(List<ListItem> cloudItems) async {
    // 1. Get all unique item names to prevent redundant queries
    final uniqueNames = cloudItems.map((e) => e.name).whereType<String>().toSet().toList();
    if (uniqueNames.isEmpty) return;

    // 2. Do ONE database query to fetch all matching master products
    final existingMasters = await isar.masterProducts
        .filter()
        .anyOf(uniqueNames, (q, String name) => q.nameEqualTo(name))
        .findAll();

    List<MasterProduct> mastersToUpdate = [];
    
    for (var item in cloudItems) {
      if (item.name == null || item.emoji == null || item.emoji == '🛒') continue;
      
      // Look for it in our in-memory list (fast)
      final masterIndex = existingMasters.indexWhere((m) => m.name == item.name);
      
      if (masterIndex != -1) {
        final master = existingMasters[masterIndex];
        if (master.emoji != item.emoji) {
          master.emoji = item.emoji!;
          // Only add if we haven't already added it to our update list
          if (!mastersToUpdate.contains(master)) mastersToUpdate.add(master);
        }
      } else {
        // We don't have this item at all! Create a new one.
        final newMaster = MasterProduct()
          ..name = item.name!
          ..emoji = item.emoji!
          ..defaultShops = [];
        
        // Add to our lists so we don't duplicate it in this loop
        existingMasters.add(newMaster); 
        mastersToUpdate.add(newMaster);
      }
    }

    // 3. Do ONE database write to save everything
    if (mastersToUpdate.isNotEmpty) {
      await isar.writeTxn(() async {
        await isar.masterProducts.putAll(mastersToUpdate);
      });
    }
  }
}