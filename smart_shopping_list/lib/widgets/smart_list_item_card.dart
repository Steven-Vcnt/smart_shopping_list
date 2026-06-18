import 'package:flutter/material.dart';
import '../models/database_models.dart';

class SmartListItemCard extends StatelessWidget {
  final ListItem item;
  final bool isExpanded;
  final bool isBlueprint;
  
  // NEW: We pass down the available shops and a toggle function
  final List<String> allShops; 
  final Function(String shop, bool isSelected) onShopToggled; 
  
  final VoidCallback onTap;
  final VoidCallback onEmojiTap;
  final Function(bool?) onToggle;
  final Function(double) onQuantityChange;

  const SmartListItemCard({
    super.key,
    required this.item,
    required this.isExpanded,
    this.isBlueprint = false,
    required this.allShops,
    required this.onShopToggled,
    required this.onTap,
    required this.onEmojiTap,
    required this.onToggle,
    required this.onQuantityChange,
  });

  @override
  Widget build(BuildContext context) {
    final safeQty = item.quantity ?? 1.0;
    final qtyString = safeQty == safeQty.truncateToDouble() ? safeQty.toInt().toString() : safeQty.toString();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: isBlueprint
                ? const Padding(padding: EdgeInsets.only(left: 8.0, right: 8.0), child: Icon(Icons.circle, size: 10, color: Colors.grey))
                : Checkbox(value: item.isChecked, onChanged: onToggle),
            title: Row(
              children: [
                GestureDetector(onTap: onEmojiTap, child: Text(item.emoji ?? '🛒', style: const TextStyle(fontSize: 22))),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.name ?? '',
                    style: TextStyle(
                      decoration: item.isChecked && !isBlueprint ? TextDecoration.lineThrough : null,
                      color: item.isChecked && !isBlueprint ? Colors.grey : Colors.black87,
                      fontWeight: item.isChecked && !isBlueprint ? FontWeight.normal : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            trailing: !isExpanded
                ? (safeQty == 1.0 ? const SizedBox.shrink() : Text('x$qtyString', style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 16)))
                : const Icon(Icons.keyboard_arrow_up, color: Colors.grey),
            onTap: isBlueprint ? null : onTap,
          ),
          
          if (isExpanded && !isBlueprint)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // QUANTITY CONTROLS
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(style: IconButton.styleFrom(backgroundColor: Colors.red.shade50), icon: const Icon(Icons.remove, color: Colors.red), onPressed: () => onQuantityChange(-1)),
                      const SizedBox(width: 12),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)), child: Text(qtyString, style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 16))),
                      const SizedBox(width: 12),
                      IconButton(style: IconButton.styleFrom(backgroundColor: Colors.green.shade50), icon: const Icon(Icons.add, color: Colors.green), onPressed: () => onQuantityChange(1)),
                    ],
                  ),
                  const Divider(),
                  // ON-THE-FLY SHOP EDITOR
                  const Text('Assigned Shops:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: -4.0, // Tighter vertical spacing
                    children: allShops.map((shopName) {
                      final isSelected = item.defaultShops.contains(shopName);
                      return FilterChip(
                        label: Text(shopName, style: const TextStyle(fontSize: 11)),
                        selected: isSelected,
                        onSelected: (val) => onShopToggled(shopName, val),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
              ),
            )
        ],
      ),
    );
  }
}