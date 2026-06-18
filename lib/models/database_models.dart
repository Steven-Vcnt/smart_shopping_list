import 'package:isar/isar.dart';

// This line is required for Isar code generation.
// You will see a red error here until we run the generator!
part 'database_models.g.dart';

// Define the behaviors for our lists
enum ListType { 
  restock,    // 🛒 The Smart Superstore (Uses Waze routing & Shop Chips)
  quickRun,   // ⚡ The Corner Store (Simple checklist, no routing)
  reusable,   // 🧳 Packing lists (Items uncheck on reset)
  blueprint   // 📋 Recipes/Templates (Read-only, copies to other lists)
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
  String? firebaseId; // Links this local list to the cloud document
  
  DateTime? lastSynced; // Remembers the last time we pushed to the cloud

  // --- NEW: COLLABORATION PROPERTIES ---
  String? ownerEmail; // Tracks who created the list
  String? ownerUid;   // The Firebase UID of the owner
  List<String> sharedWith = []; // Emails of the people allowed to see/edit this list

  List<ListItem> items = [];
}

@embedded
class ListItem {
  String? name;
  bool isChecked = false;
  String? emoji;
  double? quantity;
  String? unit;
  
  // Now a list!
  List<String> defaultShops = []; 
}

// --- MASTERBASE MODELS ---

@collection
class MasterProduct {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String name;

  String? emoji;
  String? defaultCategory;
  
  // Now a list so a product can belong to multiple shops!
  List<String> defaultShops = []; 

  List<ShopHabit> shopHabits = [];
  
  // --- NEW: SPATIAL LEARNING FIELDS ---
  List<ShopPosition> shopPositions = [];

  // --- NEW: PREDICTIVE INTELLIGENCE FIELDS ---
  int cycleDays = 14;           // How often user buys this (default 2 weeks)
  DateTime? lastPurchasedAt;    // Used to calculate the urgency score
  List<CompanionItem> companions = []; // Used to suggest paired items
}

// --- NEW: COMPANION MODEL FOR SUGGESTIONS ---
@embedded
class CompanionItem {
  String? productName;
  double weight = 0.0; // Probability (0.0 to 1.0)
}

@embedded
class ShopHabit {
  String? shopName;
  int count = 0;
}

// --- NEW: SHOP POSITION FOR ROUTING ---
@embedded
class ShopPosition {
  String? shopName;
  double aisleOrder = 99.0; // Default to end of list
}

// --- DYNAMIC SHOP MODEL ---

@collection
class UserShop {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String name;

  // --- NEW: GEOFENCING FIELDS ---
  double? lat;
  double? lng;
  double radius = 50.0; // Default 50m radius
}