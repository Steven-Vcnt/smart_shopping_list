import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:isar/isar.dart';
import '../models/database_models.dart';

// 1. NEW: A unified class to hold both Isar history and JSON dictionary items
class GrocerySuggestion {
  final String name;
  final String? emoji;
  final List<String> defaultShops;
  final bool isFromHistory;

  GrocerySuggestion({
    required this.name,
    this.emoji,
    required this.defaultShops,
    required this.isFromHistory,
  });
}

class AddItemDialog extends StatefulWidget {
  final Isar isar;
  final Function(String name, String? emoji, double quantity, List<String> shops) onAdd;

  const AddItemDialog({super.key, required this.isar, required this.onAdd});

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController(text: '1');
  
  List<UserShop> _availableShops = [];
  List<String> _selectedShops = []; 
  
  // 2. NEW: Updated state variables for smart search
  List<GrocerySuggestion> _suggestions = [];
  List<Map<String, dynamic>> _frenchDatabase = [];
  String? _currentEmoji; // Tracks the emoji dynamically as they type

  @override
  void initState() {
    super.initState();
    _loadData(); // Updated to load both Shops and the French Dictionary
  }

  Future<void> _loadData() async {
    // Load Isar shops
    final shops = await widget.isar.userShops.where().findAll();
    
    // Load French Dictionary from assets
    List<Map<String, dynamic>> frenchDb = [];
    try {
      final String jsonString = await rootBundle.loadString('assets/french_grocery_database.json');
      final Map<String, dynamic> jsonData = jsonDecode(jsonString);
      if (jsonData['items'] != null) {
        frenchDb = List<Map<String, dynamic>>.from(jsonData['items']);
      }
    } catch (e) {
      debugPrint("Could not load French database: $e");
    }

    setState(() {
      _availableShops = shops;
      _frenchDatabase = frenchDb;
    });
  }

  // 3. NEW: The Intelligent Search Engine
  Future<void> _searchDatabase(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _currentEmoji = null;
      });
      return;
    }

    final cleanQuery = query.toLowerCase().trim();
    List<GrocerySuggestion> combinedResults = [];

    // Step A: Search Isar (Personal History)
    final historyResults = await widget.isar.masterProducts
        .filter()
        .nameContains(cleanQuery, caseSensitive: false) // Using contains is better for "sans gluten", etc.
        .findAll();
    
    for (var r in historyResults) {
      combinedResults.add(GrocerySuggestion(
        name: r.name ?? '',
        emoji: r.emoji,
        defaultShops: r.defaultShops,
        isFromHistory: true,
      ));
    }

    // Step B: Search French Dictionary (Fallbacks)
    for (var item in _frenchDatabase) {
      final itemName = item['name'] as String;
      // Only add if it's not already in their personal history!
      if (itemName.toLowerCase().contains(cleanQuery) && 
          !combinedResults.any((s) => s.name.toLowerCase() == itemName.toLowerCase())) {
        combinedResults.add(GrocerySuggestion(
          name: itemName,
          emoji: item['emoji'] as String?,
          defaultShops: [],
          isFromHistory: false,
        ));
      }
    }

    // Step C: Auto-Emoji Detection (If they type exactly without tapping)
    String? matchedEmoji;
    try {
      final exactMatch = combinedResults.firstWhere((s) => s.name.toLowerCase() == cleanQuery);
      matchedEmoji = exactMatch.emoji;
    } catch (_) {
      // No exact match yet
    }

    setState(() {
      _suggestions = combinedResults.take(5).toList(); // Keep UI clean by limiting to top 5
      _currentEmoji = matchedEmoji;
    });
  }

  void _submit(String name, {String? emoji, List<String>? shops}) {
    double qty = double.tryParse(_qtyController.text) ?? 1.0;
    // Prioritize the tapped emoji, fallback to the auto-detected emoji, then null
    widget.onAdd(name, emoji ?? _currentEmoji, qty, shops ?? _selectedShops);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un produit'),
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
                    decoration: const InputDecoration(labelText: 'Qté'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Rechercher...',
                      // 4. NEW: Shows the emoji dynamically as they type!
                      prefixIcon: _currentEmoji != null 
                          ? Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Text(_currentEmoji!, style: const TextStyle(fontSize: 18)),
                            )
                          : const Icon(Icons.search, size: 20),
                    ),
                    onChanged: _searchDatabase,
                    onSubmitted: (value) => _submit(value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (_availableShops.isNotEmpty) ...[
              const Text('Disponible dans :', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                      // NEW: Visual indicator if it's from their personal history
                      trailing: product.isFromHistory 
                          ? const Icon(Icons.history, size: 16, color: Colors.grey)
                          : null,
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