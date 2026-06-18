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
  
  // This lets our UI listen to the current status (for our top banner!)
  final ValueNotifier<SyncState> syncState = ValueNotifier(SyncState.offline);
  
  StreamSubscription? _connectivitySub;
  StreamSubscription? _authSub;

  SyncService(this.isar) {
    _initListeners();
  }

  void _initListeners() {
    // 1. Listen for internet connection changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (!results.contains(ConnectivityResult.none)) {
        syncNow();
      } else {
        syncState.value = SyncState.offline;
      }
    });
    
    // 2. Listen for Auth changes (Fixes Bug #1: Race Condition)
    // This fires immediately when the user is confirmed logged in on startup.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        syncNow();
      } else {
        syncState.value = SyncState.offline; // Reset state if user logs out
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

    // 1. Check if we actually have internet before trying to push/pull
    final connectivityResults = await Connectivity().checkConnectivity();
    if (connectivityResults.contains(ConnectivityResult.none)) {
      syncState.value = SyncState.offline;
      return;
    }

    try {
      syncState.value = SyncState.syncing;
      
      // 2. Proceed with sync safely
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    // Fixes Bug #2: Use Filter.or to pull lists we own AND lists shared with us
    final snapshot = await _firestore.collection('shared_lists')
        .where(
          Filter.or(
            Filter('ownerEmail', isEqualTo: user.email),
            Filter('sharedWith', arrayContains: user.email),
          ),
        )
        .get();

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

        await _learnEmojisFromCloud(parsedItems);
        
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
    _authSub?.cancel(); // Don't forget to cancel our new auth listener to prevent memory leaks!
    syncState.dispose();
  }

  Future<void> _learnEmojisFromCloud(List<ListItem> cloudItems) async {
    await isar.writeTxn(() async {
      for (var item in cloudItems) {
        if (item.name != null && item.emoji != null && item.emoji != '🛒') {
          // Check if we have this product locally
          final master = await isar.masterProducts.where().nameEqualTo(item.name!).findFirst();
          
          if (master != null && master.emoji != item.emoji) {
            // Our partner used a different/better emoji! Let's learn it.
            master.emoji = item.emoji;
            await isar.masterProducts.put(master);
          } else if (master == null) {
            // Our partner added a totally new item we've never seen! Let's save it.
            final newMaster = MasterProduct()
              ..name = item.name!
              ..emoji = item.emoji!
              ..defaultShops = [];
            await isar.masterProducts.put(newMaster);
          }
        }
      }
    });
  }
}