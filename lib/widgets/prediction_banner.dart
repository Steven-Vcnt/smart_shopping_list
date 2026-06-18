import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../models/database_models.dart';

class PredictionBanner extends StatelessWidget {
  final Isar isar;
  final List<ListItem> currentItems;
  final Function(String name, String? emoji, double quantity) onAdd;

  const PredictionBanner({
    super.key, 
    required this.isar, 
    required this.currentItems, 
    required this.onAdd
  });

  // This logic finds items that are "due" based on their cycle
  Future<List<MasterProduct>> _getSuggestions() async {
    final allProducts = await isar.masterProducts.where().findAll();
    
    return allProducts.where((p) {
      if (p.lastPurchasedAt == null) return false;
      
      // Calculate Urgency: daysSince / cycleDays
      final daysSince = DateTime.now().difference(p.lastPurchasedAt!).inDays;
      final score = daysSince / p.cycleDays;
      
      // Suggest if it's > 80% through its cycle and NOT already in the list
      bool isAlreadyInList = currentItems.any((i) => i.name == p.name);
      return score >= 0.8 && !isAlreadyInList;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MasterProduct>>(
      future: _getSuggestions(),
      builder: (context, snapshot) {
        // If there are no suggestions, shrink to 0 height so it's invisible
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 60,
          color: Colors.blue.shade50, // A subtle background color
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: snapshot.data!.map((p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: ActionChip(
                avatar: Text(p.emoji ?? '🛒'),
                label: Text('Besoin de ${p.name} ?'), // "Need [item]?" in French
                onPressed: () {
                   // When tapped, immediately add it to the list!
                   onAdd(p.name!, p.emoji, 1.0);
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