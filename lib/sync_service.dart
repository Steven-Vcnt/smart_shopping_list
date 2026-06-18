import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'models/database_models.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum SyncState { offline, syncing, synced, error }

class SyncService {
  final Isar isar;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // This lets our UI listen to the current status (for our top banner!)
  final ValueNotifier<SyncState> syncState = ValueNotifier(SyncState.offline);
  
  StreamSubscription? _connectivitySub;

  SyncService(this.isar) {
    _initNetworkListener();
  }

  void _initNetworkListener() {
    // Listen for internet connection changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (!results.contains(ConnectivityResult.none)) {
        syncNow();
      } else {
        syncState.value = SyncState.offline;
      }
    });
    
    // Attempt an initial sync on startup
    syncNow();
  }

  Future<void> syncNow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("Sync skipped: No user logged in.");
      return; 
    }

    // 2. Proceed with sync only if user exists
    await _pushLocalChangesToCloud();

    // 1. Check if we actually have internet before trying
    final connectivityResults = await Connectivity().checkConnectivity();
    if (connectivityResults.contains(ConnectivityResult.none)) {
      syncState.value = SyncState.offline;
      return;
    }

    try {
      syncState.value = SyncState.syncing;
      
      await _pushLocalChangesToCloud();
      await _pullCloudChangesToLocal();

      syncState.value = SyncState.synced;
    } catch (e) {
      debugPrint('Sync Error: $e');
      syncState.value = SyncState.error;
    }
  }

  // --- PUSH: Local to Cloud ---
  Future<void> _pushLocalChangesToCloud() async {
    final localLists = await isar.smartLists.where().findAll();
    final batch = _firestore.batch();

    for (var list in localLists) {
      // If it has never been synced, OR it was modified after the last sync
      if (list.firebaseId == null || (list.lastSynced == null || list.lastModified.isAfter(list.lastSynced!))) {
        
        DocumentReference docRef;
        if (list.firebaseId == null) {
          docRef = _firestore.collection('shared_lists').doc(); // Generate new Cloud ID
          list.firebaseId = docRef.id;
        } else {
          docRef = _firestore.collection('shared_lists').doc(list.firebaseId);
        }

        // Convert the ListItems to JSON for Firebase
        final itemsJson = list.items.map((item) => {
          'name': item.name,
          'isChecked': item.isChecked,
          'emoji': item.emoji,
          'quantity': item.quantity,
          'defaultShops': item.defaultShops,
        }).toList();

        // Get the currently logged-in Google User
     final currentUser = FirebaseAuth.instance.currentUser;

     batch.set(docRef, {
          'name': list.name,
          'type': list.type.name,
          'lastModified': list.lastModified.toIso8601String(),
          'ownerEmail': currentUser?.email ?? 'anonymous',
          'ownerUid': currentUser?.uid ?? 'unknown',
          // NEW: Push the shared emails to the cloud!
          'sharedWith': list.sharedWith, 
          'items': itemsJson,
        }, SetOptions(merge: true));

        // Update local timestamp so we know it's synced
        list.lastSynced = DateTime.now();
        await isar.writeTxn(() async {
          await isar.smartLists.put(list);
        });
      }
    }
    await batch.commit();
  }

  // --- PULL: Cloud to Local ---
  Future<void> _pullCloudChangesToLocal() async {
    final snapshot = await _firestore.collection('shared_lists').get();

    for (var doc in snapshot.docs) {
      final cloudData = doc.data();
      final cloudModified = DateTime.parse(cloudData['lastModified']);
      
      // Find if we already have this list locally
      var localList = await isar.smartLists.where().firebaseIdEqualTo(doc.id).findFirst();

      // If we don't have it, or the cloud version is newer than ours
      if (localList == null || localList.lastModified.isBefore(cloudModified)) {
        
        final List<dynamic> itemsData = cloudData['items'] ?? [];
        final parsedItems = itemsData.map((itemMap) => ListItem()
          ..name = itemMap['name']
          ..isChecked = itemMap['isChecked'] ?? false
          ..emoji = itemMap['emoji']
          ..quantity = (itemMap['quantity'] as num?)?.toDouble()
          ..defaultShops = List<String>.from(itemMap['defaultShops'] ?? [])
        ).toList();

        final updatedList = localList ?? SmartList()
          ..firebaseId = doc.id
          ..name = cloudData['name']
          ..type = ListType.values.firstWhere((e) => e.name == cloudData['type'], orElse: () => ListType.restock);

        updatedList.items = parsedItems;
        updatedList.lastModified = cloudModified;
        updatedList.lastSynced = DateTime.now();

        await isar.writeTxn(() async {
          await isar.smartLists.put(updatedList);
        });
      }
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
    syncState.dispose();
  }
}