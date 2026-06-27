import 'package:isar/isar.dart';

// This line is required for Isar code generation.
part 'database_models.g.dart';

// Define the behaviors for our lists
enum ListType { 
  restock,    // 🛒 The Smart Superstore (Uses Waze routing & Shop Chips)
  quickRun,   // ⚡ The Corner Store (Simple checklist, no routing)
  reusable,   // 🧳 Packing lists (Items uncheck on reset)
  blueprint   // 📋 Recipes/Templates (Read-only, copies to other lists)
}

// --- THE GLOBAL TAXONOMY (French Localization) ---
enum ItemCategory {
  produce("🥬 Fruits & Légumes"),
  bakery("🥖 Boulangerie & Pâtisserie"),
  meatSeafood("🥩 Boucherie & Poissonnerie"),
  dairy("🧀 Frais & Crémerie"),
  pantry("🥫 Épicerie Salée"),
  snacks("🍬 Épicerie Sucrée"),
  breakfast("☕ Petit-déjeuner"),
  beverages("🧃 Boissons"),
  alcohol("🍷 Cave & Alcools"),
  frozen("🧊 Surgelés"),
  personalCare("🧴 Hygiène & Beauté"),
  household("🧻 Entretien & Animaux"),
  unmapped("🛒 Autre");

  final String label;
  const ItemCategory(this.label);
}

@collection
class SmartList {
  Id id = Isar.autoIncrement;

  late String name;

  @enumerated
  late ListType type;

  late DateTime lastModified;
  
  // --- SYNC PROPERTIES ---
  @Index(unique: true, replace: true)
  String? firebaseId; 
  
  DateTime? lastSynced; 

  // --- COLLABORATION PROPERTIES ---
  String? ownerEmail; 
  String? ownerUid;   
  List<String> sharedWith = []; 

  List<ListItem> items = [];
}

@embedded
class ListItem {
  String? name;
  bool isChecked = false;
  String? emoji;
  double? quantity;
  String? unit;
  List<String> defaultShops = []; 
}

// --- MASTERBASE MODELS ---

@collection
class MasterProduct {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String name;

  String? emoji;
  
  // Assigns the product to a Zone for Waze Routing
  @enumerated
  ItemCategory category = ItemCategory.unmapped; 
  
  List<String> defaultShops = []; 
  List<ShopHabit> shopHabits = [];
  
  // --- PREDICTIVE INTELLIGENCE FIELDS ---
  int cycleDays = 14;           
  DateTime? lastPurchasedAt;    
  List<CompanionItem> companions = []; 

  // --- SYNC PROPERTIES ---
  @Index()
  String? firebaseId;
  DateTime lastModified = DateTime.now();
  DateTime? lastSynced;
}

@embedded
class CompanionItem {
  String? productName;
  double weight = 0.0; 
}

@embedded
class ShopHabit {
  String? shopName;
  int count = 0;
}

// --- NEW: SHOP POSITION FOR ROUTING ---
@embedded
class ZonePosition {
  @enumerated
  ItemCategory category = ItemCategory.unmapped;
  double aisleOrder = 99.0; // 1.0 is entrance, 99.0 is exit
}

// --- DYNAMIC SHOP MODEL ---

@collection
class UserShop {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String name;

  // --- GEOFENCING FIELDS ---
  double? lat;
  double? lng;
  double radius = 50.0; 

  // --- NEW: SYNC & ROUTING FIELDS ---
  String? firebaseId;
  DateTime lastModified = DateTime.now();
  DateTime? lastSynced;
  
  // The Waze Route: The learned layout of zones for this specific store
  List<ZonePosition> zoneLayout = []; 
}