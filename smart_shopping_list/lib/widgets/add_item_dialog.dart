import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../models/database_models.dart';

class AddItemDialog extends StatefulWidget {
  final Isar isar;
  // UPDATED: Now expects a List<String> of shops
  final Function(String name, String? emoji, double quantity, List<String> shops) onAdd;

  const AddItemDialog({super.key, required this.isar, required this.onAdd});

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController(text: '1');
  List<MasterProduct> _suggestions = [];
  
  List<UserShop> _availableShops = [];
  // NEW: Track multiple selected shops
  List<String> _selectedShops = []; 

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    final shops = await widget.isar.userShops.where().findAll();
    setState(() => _availableShops = shops);
  }

  Future<void> _searchDatabase(String query) async {
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    final results = await widget.isar.masterProducts
        .filter()
        .nameStartsWith(query, caseSensitive: false)
        .findAll();
    setState(() => _suggestions = results);
  }

  void _submit(String name, {String? emoji, List<String>? shops}) {
    double qty = double.tryParse(_qtyController.text) ?? 1.0;
    widget.onAdd(name, emoji, qty, shops ?? _selectedShops);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Product'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _qtyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Qty'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Search...'),
                    onChanged: _searchDatabase,
                    onSubmitted: (value) => _submit(value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // THE NEW MULTI-SELECT SHOP BUTTONS
            if (_availableShops.isNotEmpty) ...[
              const Text('Available in:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: _availableShops.map((shop) {
                  final isSelected = _selectedShops.contains(shop.name);
                  return FilterChip(
                    label: Text(shop.name, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) _selectedShops.add(shop.name);
                        else _selectedShops.remove(shop.name);
                      });
                    },
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],

            if (_suggestions.isNotEmpty)
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final product = _suggestions[index];
                    return ListTile(
                      leading: Text(product.emoji ?? '🛒', style: const TextStyle(fontSize: 24)),
                      title: Text(product.name),
                      // Display the shops as a joined string
                      subtitle: product.defaultShops.isNotEmpty 
                          ? Text(product.defaultShops.join(', '), style: TextStyle(color: Colors.blue.shade700, fontSize: 12))
                          : null,
                      onTap: () => _submit(product.name, emoji: product.emoji, shops: product.defaultShops),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}