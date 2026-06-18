import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:share_plus/share_plus.dart'; // NEW: The native share package!
import 'models/database_models.dart';
import 'widgets/add_item_dialog.dart';
import 'widgets/smart_list_item_card.dart';
import 'widgets/sync_banner.dart'; 
import 'sync_service.dart';

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

  @override
  void initState() {
    super.initState();
    _currentList = widget.smartList;
    _loadShops();
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
      restockList!.items = updatedItems;
      restockList!.lastModified = DateTime.now();
      await widget.isar.smartLists.put(restockList!);
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

  // --- UPDATED: THE SHARE DIALOG WITH TEXT MESSAGE TRIGGER ---
  void _showShareDialog() {
    final TextEditingController emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share List'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the Google email of the person you want to share this list with.'),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final email = emailController.text.trim().toLowerCase();
              if (email.isNotEmpty && email.contains('@')) {
                setState(() {
                  if (!_currentList.sharedWith.contains(email)) {
                    _currentList.sharedWith.add(email);
                  }
                });
                _saveListState(); 
                Navigator.pop(context); // Close the dialog
                
                // NEW: Pop open the native Android/iOS share sheet!
                Share.share(
                  'Hey! I just shared the "${_currentList.name}" list with you on Smart Grocery. Open the app to see it!',
                );
              }
            },
            child: const Text('Share'),
          ),
        ],
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
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Un-crossed "$cleanName" from your list!')));
        } else {
          _currentList.items[existingIndex].quantity = (_currentList.items[existingIndex].quantity ?? 1.0) + quantity;
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Increased quantity for "$cleanName"!')));
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
      builder: (ctx) => EmojiPicker(
        onEmojiSelected: (category, emoji) {
          setState(() { _currentList.items[index].emoji = emoji.emoji; _currentList.items = List.from(_currentList.items); });
          _saveListState();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showAddItemDialog() {
    showDialog(context: context, builder: (context) => AddItemDialog(isar: widget.isar, onAdd: _addItem));
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
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Share List',
            onPressed: _showShareDialog,
          ),
          if (_currentList.type == ListType.restock || _currentList.type == ListType.quickRun)
            IconButton(icon: const Icon(Icons.delete_sweep), onPressed: () { setState(() => _currentList.items = _currentList.items.where((item) => !item.isChecked).toList()); _saveListState(); }),
          if (_currentList.type == ListType.reusable)
            IconButton(icon: const Icon(Icons.refresh), onPressed: () { setState(() { for (var item in _currentList.items) { item.isChecked = false; } _currentList.items = List.from(_currentList.items); }); _saveListState(); }),
        ],
      ),
      body: Column(
        children: [
          SyncBanner(syncService: widget.syncService),
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
                          onToggle: (val) { setState(() => _currentList.items[realIndex].isChecked = val!); _sortList(); },
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