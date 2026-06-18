import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../models/database_models.dart';

class _Prediction {
  final MasterProduct product;
  final String label;

  _Prediction(this.product, this.label);
}

class PredictionBanner extends StatefulWidget {
  final Isar isar;
  final List<ListItem> currentItems;
  final Function(String name, String? emoji, double quantity) onAdd;

  const PredictionBanner({
    super.key, 
    required this.isar, 
    required this.currentItems, 
    required this.onAdd
  });

  @override
  State<PredictionBanner> createState() => _PredictionBannerState();
}

class _PredictionBannerState extends State<PredictionBanner> {
  Future<List<_Prediction>> _getSuggestions() async {
    final allProducts = await widget.isar.masterProducts.where().findAll();
    List<_Prediction> predictions = [];
    
    final currentUncheckedNames = widget.currentItems.where((i) => !i.isChecked).map((i) => i.name).toSet();
    final allCurrentNames = widget.currentItems.map((i) => i.name).toSet();

    for (var p in allProducts) {
      // 1. Time-based Replenishment
      if (p.lastPurchasedAt != null) {
        final daysSince = DateTime.now().difference(p.lastPurchasedAt!).inDays;
        final score = daysSince / p.cycleDays;
        
        // Suggest if it's > 80% through its cycle and NOT in the list as UNCHECKED
        // If it's checked, it will be suggested so the user can "uncheck" it via onAdd
        if (score >= 0.8 && !currentUncheckedNames.contains(p.name)) {
          predictions.add(_Prediction(p, 'Besoin de ${p.name} ?'));
          continue; 
        }
      }
      
      // 2. Companion Product Recommendations
      if (!allCurrentNames.contains(p.name)) {
        bool isCompanion = false;
        String? linkedItemName;
        
        for (var currentItem in widget.currentItems) {
           final currentMaster = allProducts.firstWhere(
             (m) => m.name == currentItem.name, 
             orElse: () => MasterProduct()
           );
           
           if (currentMaster.companions.any((c) => c.productName == p.name)) {
              isCompanion = true;
              linkedItemName = currentItem.name;
              break;
           }
        }
        
        if (isCompanion) {
           predictions.add(_Prediction(p, 'Avec $linkedItemName, prenez ${p.name} ?'));
        }
      }
    }
    
    // --- NEW: Explicitly inject Mozzarella if Pizza is in the list, even if Mozzarella isn't in DB yet ---
    final hasPizza = widget.currentItems.any((i) => i.name != null && i.name!.toLowerCase().contains('pizza'));
    final hasMozzarella = allCurrentNames.any((n) => n?.toLowerCase().contains('mozzarella') ?? false);
    
    if (hasPizza && !hasMozzarella) {
       // Check if we haven't already suggested it
       if (!predictions.any((pred) => pred.product.name.toLowerCase().contains('mozzarella'))) {
          final linkedItemName = widget.currentItems.firstWhere((i) => i.name!.toLowerCase().contains('pizza')).name;
          final mockMozzarella = MasterProduct()
             ..name = "Mozzarella"
             ..emoji = "🧀";
             
          predictions.add(_Prediction(mockMozzarella, 'Avec $linkedItemName, prenez Mozzarella ?'));
       }
    }
    
    return predictions;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Prediction>>(
      future: _getSuggestions(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 60,
          color: Colors.blue.shade50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: snapshot.data!.map((pred) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: ActionChip(
                avatar: Text(pred.product.emoji ?? '🛒'),
                label: Text(pred.label), 
                onPressed: () {
                   widget.onAdd(pred.product.name, pred.product.emoji, 1.0);
                   setState(() {}); // refresh banner to remove suggestion
                },
                backgroundColor: Colors.white,
                elevation: 1,
                side: BorderSide(color: Colors.blue.shade200),
              ),
            )).toList(),
          ),
        );
      },
    );
  }
}