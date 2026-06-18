import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'models/database_models.dart';
import 'widgets/add_item_dialog.dart';
import 'widgets/smart_list_item_card.dart';
import 'widgets/sync_banner.dart';
import 'widgets/prediction_banner.dart';
import 'widgets/shared_users_bottom_sheet.dart';
import 'widgets/store_detection_banner.dart';
import 'services/location_routing_service.dart';
import 'sync_service.dart';
import 'dart:async';

class ListDetailScreen extends StatefulWidget {
  final Isar isar;
  final SmartList smartList;
  final SyncService syncService; 

  const ListDetailScreen({
    super.key, 
    required this.isar, 
    required this.smartList,
    required this.syncService, 
  });

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  late SmartList _currentList;
  List<UserShop> _shops = [];
  String _activeTab = 'All'; 
  bool _isLoadingShops = true;
  int? _expandedItemIndex;
  
  // --- Spatial Routing & Heuristics ---
  late LocationRoutingService _locationService;
  
  // FIX: Using the correct DetectedShop types from your routing service
  StreamSubscription<DetectedShop?>? _shopSubscription;
  UserShop? _detectedShop;       // Confirmed active shop (Local Database Model)
  DetectedShop? _pendingShop;    // Detected but not yet confirmed by user (GPS Model)
  
  Map<String, double> _itemAisleOrders = {};
  final List<String> _checkSequence = [];
  
  // --- Track the last checked item for our Undo button ---
  String? _lastCheckedItemName;

  @override
  void initState() {
    super.initState();
    _currentList = widget.smartList;
    _locationService = LocationRoutingService(widget.isar);
    _initLocationTracking();
    _loadShops();
  }
  
  @override
  void dispose() {
    _shopSubscription?.cancel();
    _locationService.stopTracking();
    _processHeuristicsBatch();
    super.dispose();
  }

  Future<void> _initLocationTracking() async {
    await _locationService.startTracking();
    _shopSubscription = _locationService.currentShopStream.listen((shop) async {
      if (!mounted) return;
      if (shop == null) {
        // Left all known geofences — clear the confirmed shop silently
        setState(() {
          _detectedShop = null;
          _pendingShop = null;
        });
        await _updateAisleOrdersAndSort();
      } else if (shop.name != _detectedShop?.name) {
        // FIX: Compare by .name instead of .id, and assign DetectedShop!
        // Don't auto-confirm! Show the banner and let the user decide.
        setState(() => _pendingShop = shop);
      }
    });
  }

  /// Called when user taps "Yes!" on the StoreDetectionBanner.
  Future<void> _confirmDetectedShop(DetectedShop shop) async {
    // FIX: Safely map the incoming GPS DetectedShop to our local UserShop database model
    final matchedUserShop = _shops.firstWhere(
      (s) => s.name == shop.name,
      orElse: () => UserShop()..name = shop.name,
    );

    setState(() {
      _pendingShop = null;
      _detectedShop = matchedUserShop;
      _activeTab = matchedUserShop.name;
    });
    await _updateAisleOrdersAndSort();
  }

  /// Called when user picks a different shop from the override picker.
  Future<void> _overrideDetectedShop(UserShop shop) async {
    setState(() {
      _pendingShop = null;
      _detectedShop = shop;
      _activeTab = shop.name;
    });
    await _updateAisleOrdersAndSort();
  }

  /// Called when user taps "Change" → "I'm not in a store".
  void _dismissDetection() {
    setState(() {
      _pendingShop = null;
      _detectedShop = null;
    });
  }

  Future<void> _updateAisleOrdersAndSort() async {
    if (_detectedShop == null) {
      _itemAisleOrders.clear();
      await _sortList();
      return;
    }

    final itemNames = _currentList.items.map((e) => e.name ?? '').toList();
    final masters = await widget.isar.masterProducts.filter()
      .anyOf(itemNames, (q, String name) => q.nameEqualTo(name)).findAll();
    
    Map<String, double> newAisleOrders = {};
    for (var master in masters) {
      final pos = master.shopPositions.firstWhere(
        (p) => p.shopName == _detectedShop!.name,
        orElse: () => ShopPosition()..shopName = _detectedShop!.name..aisleOrder = 99.0,
      );
      newAisleOrders[master.name] = pos.aisleOrder;
    }

    if (mounted) {
      setState(() {
        _itemAisleOrders = newAisleOrders;
      });
      await _sortList();
    }
  }

  Future<void> _processHeuristicsBatch() async {
    if (_detectedShop == null || _checkSequence.isEmpty) return;
    
    final shopName = _detectedShop!.name;
    final List<String> sequence = List.from(_checkSequence);
    
    final masters = await widget.isar.masterProducts.filter()
      .anyOf(sequence, (q, String name) => q.nameEqualTo(name)).findAll();
    
    if (masters.isEmpty) return;

    await widget.isar.writeTxn(() async {
      for (int i = 0; i < sequence.length; i++) {
        final itemName = sequence[i];
        final currentPosInSequence = (i + 1).toDouble(); 
        
        final masterIndex = masters.indexWhere((m) => m.name == itemName);
        if (masterIndex == -1) continue;
        
        final master = masters[masterIndex];
        
        int posIndex = master.shopPositions.indexWhere((p) => p.shopName == shopName);
        if (posIndex != -1) {
          // EMA: alpha = 0.3
          double oldOrder = master.shopPositions[posIndex].aisleOrder;
          master.shopPositions[posIndex].aisleOrder = (0.3 * currentPosInSequence) + (0.7 * oldOrder);
          master.shopPositions = List.from(master.shopPositions);
        } else {
          master.shopPositions = List.from(master.shopPositions)..add(
            ShopPosition()
              ..shopName = shopName
              ..aisleOrder = currentPosInSequence
          );
        }
        
        await widget.isar.masterProducts.put(master);
      }
    });
  }

  Future<void> _sendToCart() async {
    var restockList = await widget.isar.smartLists.filter().typeEqualTo(ListType.restock).findFirst();
    if (restockList == null) {
      restockList = SmartList()..name = 'My Groceries'..type = ListType.restock..lastModified = DateTime.now();
      await widget.isar.writeTxn(() async { await widget.isar.smartLists.put(restockList!); });
    }

    await widget.isar.writeTxn(() async {
      List<ListItem> updatedItems = List.from(restockList!.items);
      for (var blueprintItem in _currentList.items) {
        int existingIndex = updatedItems.indexWhere((item) => item.name?.toLowerCase() == blueprintItem.name?.toLowerCase());
        if (existingIndex != -1) {
          updatedItems[existingIndex].quantity = (updatedItems[existingIndex].quantity ?? 1.0) + (blueprintItem.quantity ?? 1.0);
        } else {
          updatedItems.add(ListItem()
            ..name = blueprintItem.name
            ..emoji = blueprintItem.emoji
            ..quantity = blueprintItem.quantity
            ..defaultShops = List.from(blueprintItem.defaultShops) 
            ..isChecked = false
          );
        }
      }
      restockList.items = updatedItems;
      restockList.lastModified = DateTime.now();
      await widget.isar.smartLists.put(restockList);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🛒 Sent ${_currentList.items.length} items to ${restockList.name}!'), backgroundColor: Colors.green.shade700, behavior: SnackBarBehavior.floating));
      Navigator.pop(context);
    }
  }

  Future<void> _loadShops() async {
    final shopsFromDb = await widget.isar.userShops.where().findAll();
    setState(() {
      _shops = shopsFromDb;
      _isLoadingShops = false;
    });
    _sortList(); 
  }

  Future<void> _sortList() async {
    setState(() {
      _currentList.items.sort((a, b) {
        if (a.isChecked && !b.isChecked) return 1;
        if (!a.isChecked && b.isChecked) return -1;
        
        // --- NEW: Spatial Sorting based on Heuristics ---
        if (_detectedShop != null && !a.isChecked && !b.isChecked) {
          final aOrder = _itemAisleOrders[a.name] ?? 99.0;
          final bOrder = _itemAisleOrders[b.name] ?? 99.0;
          return aOrder.compareTo(bOrder);
        }

        return 0; 
      });
      _expandedItemIndex = null;
    });
    _saveListState();
  }

  Future<void> _saveListState() async {
    _currentList.lastModified = DateTime.now();
    await widget.isar.writeTxn(() async { 
      await widget.isar.smartLists.put(_currentList); 
    });
    
    widget.syncService.syncNow(); 
  }

  void _showShareDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SharedUsersBottomSheet(
        currentList: _currentList,
        onListUpdated: (updatedList) {
          setState(() {});
          _saveListState();
        },
      ),
    );
  }

  Widget _buildSharedUsersAvatars() {
    final List<String> allEmails = [];
    if (_currentList.ownerEmail != null && _currentList.ownerEmail!.isNotEmpty) {
      allEmails.add(_currentList.ownerEmail!);
    }
    allEmails.addAll(_currentList.sharedWith);
    
    if (allEmails.isEmpty) {
      return IconButton(
        icon: const Icon(Icons.person_add_alt_1),
        tooltip: 'Share List',
        onPressed: _showShareDialog,
      );
    }
    
    final displayEmails = allEmails.take(3).toList();
    final extraCount = allEmails.length - displayEmails.length;
    
    return GestureDetector(
      onTap: _showShareDialog,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: (displayEmails.length * 20.0) + (extraCount > 0 ? 20.0 : 0.0) + 8.0,
              height: 32,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  for (int i = 0; i < displayEmails.length; i++)
                    Positioned(
                      left: i * 20.0,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: i == 0 ? Colors.blue.shade100 : Colors.grey.shade200,
                        child: Text(
                          displayEmails[i][0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 12, 
                            fontWeight: FontWeight.bold,
                            color: i == 0 ? Colors.blue.shade900 : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                  if (extraCount > 0)
                    Positioned(
                      left: displayEmails.length * 20.0,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.grey.shade300,
                        child: Text(
                          '+$extraCount',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addItem(String itemName, String? emoji, double quantity, List<String> shops) async {
    String cleanName = itemName.trim();
    if (cleanName.isEmpty) return;

    int existingIndex = _currentList.items.indexWhere((item) => item.name?.toLowerCase() == cleanName.toLowerCase());
    if (existingIndex != -1) {
      setState(() {
        if (_currentList.items[existingIndex].isChecked) {
          _currentList.items[existingIndex].isChecked = false;
        } else {
          _currentList.items[existingIndex].quantity = (_currentList.items[existingIndex].quantity ?? 1.0) + quantity;
        }
        _currentList.items = List.from(_currentList.items);
      });
      _sortList(); 
      return;
    }

    final existingMaster = await widget.isar.masterProducts.where().nameEqualTo(cleanName).findFirst();
    if (existingMaster == null) {
      final newMaster = MasterProduct()
        ..name = cleanName
        ..emoji = emoji ?? '🛒'
        ..defaultShops = shops;
      await widget.isar.writeTxn(() async { await widget.isar.masterProducts.put(newMaster); });
    }

    setState(() {
      final newItem = ListItem()
        ..name = cleanName
        ..isChecked = false
        ..emoji = existingMaster?.emoji ?? emoji ?? '🛒'
        ..quantity = quantity
        ..defaultShops = shops.isNotEmpty ? shops : (existingMaster?.defaultShops ?? []); 
      
      _currentList.items = [..._currentList.items, newItem];
    });
    _sortList(); 
  }

  void _updateQuantity(int index, double delta) {
    setState(() {
      double next = (_currentList.items[index].quantity ?? 1.0) + delta;
      if (next <= 0) {
        _deleteItem(index);
        _expandedItemIndex = null;
      } else {
        _currentList.items[index].quantity = next;
        _currentList.items = List.from(_currentList.items);
      }
    });
    _saveListState();
  }

  void _deleteItem(int index) {
    setState(() {
      _currentList.items.removeAt(index);
      _currentList.items = List.from(_currentList.items);
    });
    _saveListState();
  }

  void _toggleShopForItem(int index, String shopName, bool isSelected) {
    setState(() {
      if (isSelected) {
        if (!_currentList.items[index].defaultShops.contains(shopName)) {
          _currentList.items[index].defaultShops.add(shopName);
        }
      } else {
        _currentList.items[index].defaultShops.remove(shopName);
      }
      _currentList.items = List.from(_currentList.items); 
    });
    _saveListState();
    
    _updateMasterProductShops(_currentList.items[index].name!, _currentList.items[index].defaultShops);
  }

  Future<void> _updateMasterProductShops(String productName, List<String> newShops) async {
    final master = await widget.isar.masterProducts.where().nameEqualTo(productName).findFirst();
    if (master != null) {
      master.defaultShops = newShops;
      await widget.isar.writeTxn(() async { await widget.isar.masterProducts.put(master); });
    }
  }

  void _showEmojiPicker(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.5, 
        child: EmojiPicker(
          config: Config(
            bottomActionBarConfig: const BottomActionBarConfig(
              showSearchViewButton: true, 
              showBackspaceButton: true,
            ),
            searchViewConfig: const SearchViewConfig(
              hintText: 'Rechercher un emoji...', 
            ),
            categoryViewConfig: CategoryViewConfig(
              iconColorSelected: Colors.blue.shade700,
              indicatorColor: Colors.blue.shade700,
            ),
          ),
          onEmojiSelected: (category, emoji) async {
            final newEmoji = emoji.emoji;
            final itemName = _currentList.items[index].name!;

            setState(() { 
              _currentList.items[index].emoji = newEmoji; 
              _currentList.items = List.from(_currentList.items); 
            });
            _saveListState();
            
            final master = await widget.isar.masterProducts.where().nameEqualTo(itemName).findFirst();
            if (master != null) {
              master.emoji = newEmoji;
              await widget.isar.writeTxn(() async { 
                await widget.isar.masterProducts.put(master); 
              });
            }

            if (mounted) Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  void _showAddItemDialog() {
    showDialog(context: context, builder: (context) => AddItemDialog(isar: widget.isar, onAdd: _addItem));
  }

  Future<void> _toggleItemCheck(int index, bool newValue) async {
    final item = _currentList.items[index];
    final itemName = item.name;

    setState(() {
      item.isChecked = newValue;
      
      // If we check it off, save it as the "last checked" for the Undo button
      if (newValue == true) {
        _lastCheckedItemName = itemName;
        // --- NEW: Record sequence ---
        if (itemName != null && _detectedShop != null) {
           _checkSequence.remove(itemName); 
           _checkSequence.add(itemName);
        }
      } else if (_lastCheckedItemName == itemName) {
        // If they manually uncheck the item they just checked, hide the undo button
        _lastCheckedItemName = null;
        if (itemName != null) {
           _checkSequence.remove(itemName);
        }
      }
    });
    
    await _sortList();
    if (!mounted) return;

    // UPDATE PREDICTIONS: We only register a "purchase" if it's checked off
    if (newValue == true && itemName != null) {
      final master = await widget.isar.masterProducts.where().nameEqualTo(itemName).findFirst();
      if (master != null) {
        await widget.isar.writeTxn(() async {
          master.lastPurchasedAt = DateTime.now(); 
          await widget.isar.masterProducts.put(master);
        });
        
        // --- NEW: Trigger a rebuild AFTER the database update so PredictionBanner catches the new date!
        if (mounted) {
           setState(() {});
        }
      }
    }
  }

  // --- NEW: The Undo Logic ---
  Future<void> _undoLastCheck() async {
    if (_lastCheckedItemName == null) return;
    
    final itemNameToUndo = _lastCheckedItemName!;
    
    setState(() {
      // Find the item and uncheck it
      for (var item in _currentList.items) {
        if (item.name == itemNameToUndo) {
          item.isChecked = false;
          break;
        }
      }
      // Hide the Undo button now that we've used it
      _lastCheckedItemName = null;
    });
    
    await _sortList();
    if (!mounted) return;

    // Remove the "purchased" timestamp from the database so the prediction banner stays accurate
    final master = await widget.isar.masterProducts.where().nameEqualTo(itemNameToUndo).findFirst();
    if (master != null) {
       await widget.isar.writeTxn(() async {
         master.lastPurchasedAt = null; 
         await widget.isar.masterProducts.put(master);
       });
    }
  }

  @override
  Widget build(BuildContext context) {
    List<ListItem> displayedItems = _activeTab == 'All'
        ? _currentList.items
        : _currentList.items.where((item) => item.defaultShops.contains(_activeTab)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentList.name),
        actions: [
          // THE NEW UNDO BUTTON - Only shows if an item was recently checked off!
          if (_lastCheckedItemName != null)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo',
              onPressed: _undoLastCheck,
            ),
            
          _buildSharedUsersAvatars(),
          if (_currentList.type == ListType.reusable)
            IconButton(icon: const Icon(Icons.refresh), onPressed: () { setState(() { for (var item in _currentList.items) { item.isChecked = false; } _currentList.items = List.from(_currentList.items); }); _saveListState(); }),
        ],
      ),
      body: Column(
        children: [
          SyncBanner(syncService: widget.syncService),
          
          // --- Store Detection Banner (shows when geofence fires, waits for user confirmation) ---
          if (_pendingShop != null)
            StoreDetectionBanner(
              detectedShop: _pendingShop!,
              allShops: _shops,
              onConfirm: () => _confirmDetectedShop(_pendingShop!),
              onOverride: _overrideDetectedShop,
              onDismiss: _dismissDetection,
            ),

          PredictionBanner(
            isar: widget.isar,
            currentItems: _currentList.items,
            onAdd: (name, emoji, qty) => _addItem(name, emoji, qty, []),
          ),
          
          if (_currentList.type == ListType.restock) ...[
            if (_isLoadingShops) 
              const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
            else
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(label: const Text('All'), selected: _activeTab == 'All', onSelected: (selected) { if (selected) setState(() => _activeTab = 'All'); }),
                    ),
                    ..._shops.map((shop) => Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(label: Text(shop.name), selected: _activeTab == shop.name, onSelected: (selected) { if (selected) setState(() => _activeTab = shop.name); }),
                        )),
                  ],
                ),
              ),
            const Divider(height: 1),
          ],
          
          Expanded(
            child: displayedItems.isEmpty
                ? const Center(child: Text('No items to display here.'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80), 
                    itemCount: displayedItems.length,
                    itemBuilder: (context, index) {
                      final item = displayedItems[index];
                      final realIndex = _currentList.items.indexOf(item);

                      return Dismissible(
                        key: UniqueKey(),
                        direction: DismissDirection.endToStart,
                        background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20.0), color: Colors.redAccent, child: const Icon(Icons.delete, color: Colors.white)),
                        confirmDismiss: (direction) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Item?'),
                              content: Text('Are you sure you want to completely remove "${item.name}"?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.red), 
                                  onPressed: () => Navigator.pop(context, true), 
                                  child: const Text('Delete')
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (_) => _deleteItem(realIndex),
                        child: SmartListItemCard(
                          item: item,
                          isExpanded: _expandedItemIndex == realIndex,
                          isBlueprint: _currentList.type == ListType.blueprint,
                          allShops: _shops.map((s) => s.name).toList(), 
                          onShopToggled: (shopName, isSelected) => _toggleShopForItem(realIndex, shopName, isSelected), 
                          onTap: () => setState(() => _expandedItemIndex = _expandedItemIndex == realIndex ? null : realIndex),
                          onEmojiTap: () => _showEmojiPicker(realIndex),
                          onToggle: (val) {
                             if (val != null) {
                               _toggleItemCheck(realIndex, val); 
                             }
                          },
                          onQuantityChange: (delta) => _updateQuantity(realIndex, delta),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      
      bottomNavigationBar: _currentList.type == ListType.blueprint && _currentList.items.isNotEmpty
          ? SafeArea(child: Padding(padding: const EdgeInsets.all(16.0), child: FilledButton.icon(icon: const Icon(Icons.shopping_cart_checkout), label: const Text('Send to Cart', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: _sendToCart)))
          : null,
          
      floatingActionButton: FloatingActionButton(onPressed: _showAddItemDialog, child: const Icon(Icons.add)),
    );
  }
}