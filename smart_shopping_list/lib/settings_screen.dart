import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'models/database_models.dart';

class SettingsScreen extends StatefulWidget {
  final Isar isar;

  const SettingsScreen({super.key, required this.isar});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<UserShop> _shops = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  // --- DATABASE OPERATIONS ---

  Future<void> _loadShops() async {
    final shopsFromDb = await widget.isar.userShops.where().findAll();
    setState(() {
      _shops = shopsFromDb;
      _isLoading = false;
    });
  }

  Future<void> _addShop(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;

    // Prevent duplicates
    final existing = await widget.isar.userShops.where().nameEqualTo(cleanName).findFirst();
    if (existing != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shop already exists!')));
      return;
    }

    final newShop = UserShop()..name = cleanName;
    await widget.isar.writeTxn(() async {
      await widget.isar.userShops.put(newShop);
    });
    _loadShops();
  }

  Future<void> _editShop(UserShop shop, String newName) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty || cleanName == shop.name) return;

    await widget.isar.writeTxn(() async {
      shop.name = cleanName;
      await widget.isar.userShops.put(shop);
    });
    _loadShops();
  }

  Future<void> _deleteShop(UserShop shop) async {
    await widget.isar.writeTxn(() async {
      await widget.isar.userShops.delete(shop.id);
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${shop.name} deleted')),
      );
    }
    _loadShops();
  }

  // --- UI DIALOGS ---

  void _showShopDialog({UserShop? existingShop}) {
    final TextEditingController controller = TextEditingController(
      text: existingShop?.name ?? '',
    );
    final isEditing = existingShop != null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Shop' : 'Add New Shop'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Shop Name',
            hintText: 'e.g., Carrefour, Decathlon...',
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (val) {
            isEditing ? _editShop(existingShop, val) : _addShop(val);
            Navigator.pop(context);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              isEditing ? _editShop(existingShop, controller.text) : _addShop(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(UserShop shop) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Shop?'),
        content: Text('Are you sure you want to remove "${shop.name}" from your app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              _deleteShop(shop);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // --- BUILD UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Shops'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _shops.isEmpty
              ? const Center(child: Text('No shops yet. Add one!'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: _shops.length,
                  itemBuilder: (context, index) {
                    final shop = _shops[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Icon(Icons.storefront, color: Colors.blue.shade800),
                        ),
                        title: Text(shop.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.grey),
                              onPressed: () => _showShopDialog(existingShop: shop),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _confirmDelete(shop),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showShopDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Shop'),
      ),
    );
  }
}