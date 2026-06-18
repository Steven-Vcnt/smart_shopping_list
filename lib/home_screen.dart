import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'models/database_models.dart';
import 'list_detail_screen.dart';
import 'settings_screen.dart';
import 'sync_service.dart';
import 'widgets/sync_banner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class HomeScreen extends StatefulWidget {
  final Isar isar;
  // 1. Define the variable
  final SyncService syncService; 

  // 2. Add 'required this.syncService' to the constructor
  const HomeScreen({
    super.key, 
    required this.isar, 
    required this.syncService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SmartList> _lists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  // Fetch all lists from the database, sorted by most recently modified
  Future<void> _loadLists() async {
    final lists = await widget.isar.smartLists.where().sortByLastModifiedDesc().findAll();
    setState(() {
      _lists = lists;
      _isLoading = false;
    });
  }

  // Delete a list
  Future<void> _deleteList(SmartList list) async {
    await widget.isar.writeTxn(() async {
      await widget.isar.smartLists.delete(list.id);
    });
    _loadLists();
  }

  // Visual helper to give each list type a unique icon
  IconData _getIconForType(ListType type) {
    switch (type) {
      case ListType.restock:
        return Icons.shopping_cart_outlined;
      case ListType.quickRun:
        return Icons.flash_on;
      case ListType.reusable:
        return Icons.luggage_outlined;
      case ListType.blueprint:
        return Icons.menu_book_outlined;
    }
  }

  // Dialog to create a new list
  void _showAddListDialog() {
    final TextEditingController nameController = TextEditingController();
    ListType selectedType = ListType.restock;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create New List'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'List Name',
                      hintText: 'e.g., Weekly Groceries, Lasagna...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ListType>(
                    value: selectedType,
                    decoration: const InputDecoration(labelText: 'List Type'),
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: ListType.restock, child: Text('🛒 Master Restock (Smart)')),
                      DropdownMenuItem(value: ListType.quickRun, child: Text('⚡ Quick Run (Simple)')),
                      DropdownMenuItem(value: ListType.reusable, child: Text('🧳 Packing (Reusable)')),
                      DropdownMenuItem(value: ListType.blueprint, child: Text('📋 Recipe (Blueprint)')),
                    ],
                    onChanged: (ListType? newValue) {
                      if (newValue != null) {
                        setDialogState(() {
                          selectedType = newValue;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) return;

                    final newList = SmartList()
                      ..name = nameController.text.trim()
                      ..type = selectedType
                      ..lastModified = DateTime.now();

                    await widget.isar.writeTxn(() async {
                      await widget.isar.smartLists.put(newList);
                    });

                    if (context.mounted) {
                      Navigator.pop(context);
                      _loadLists();
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }
Future<void> _manualGoogleLogin() async {
    try {
      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize();
      final GoogleSignInAccount? googleUser = await googleSignIn.authenticate();
      if (googleUser == null) return;
      
      final clientAuth = await googleUser.authorizationClient?.authorizeScopes(['email', 'profile']);
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: clientAuth?.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Smart Lists'),
        actions: [
          // NEW: Real-time listener for your Google Auth state
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              final user = snapshot.data;
              
              // IF LOGGED OUT: Show a login icon
              if (user == null) {
                return IconButton(
                  icon: const Icon(Icons.account_circle_outlined, size: 28),
                  tooltip: 'Sign In',
                  onPressed: _manualGoogleLogin,
                );
              }

              // IF LOGGED IN: Show your Google Avatar and a dropdown menu
              return PopupMenuButton<String>(
                offset: const Offset(0, 45),
                icon: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.blue.shade100,
                  backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                  child: user.photoURL == null 
                      // THE FIX: Safely check if email exists and isn't empty!
                      ? Text(
                          (user.email != null && user.email!.isNotEmpty) 
                              ? user.email![0].toUpperCase() 
                              : '?', 
                          style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold)
                        )
                      : null,
                ),
                onSelected: (value) async {
                  if (value == 'settings') {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsScreen(isar: widget.isar)))
                        .then((_) => _loadLists());
                  } else if (value == 'logout') {
                    await FirebaseAuth.instance.signOut();
                    await GoogleSignIn.instance.signOut();
                  }
                },
                itemBuilder: (BuildContext context) => [
                  // Displays your connected email address
                  PopupMenuItem(
                    enabled: false,
                    // THE FIX: Provide a clean fallback if email is empty
                    child: Text(
                      (user.email != null && user.email!.isNotEmpty) ? user.email! : 'Anonymous User', 
                      style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13)
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'settings',
                    child: Row(children: [Icon(Icons.storefront, size: 20), SizedBox(width: 8), Text('Manage Shops')]),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(children: [Icon(Icons.logout, size: 20, color: Colors.red), SizedBox(width: 8), Text('Sign Out', style: TextStyle(color: Colors.red))]),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 8), // Small padding for the right edge
        ],
      ),
      // NEW: Wrap the body in a Column so the Banner sits at the top!
      body: Column(
        children: [
          // THE SYNC BANNER
          SyncBanner(syncService: widget.syncService),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _lists.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.list_alt, size: 80, color: Colors.grey.shade300), const SizedBox(height: 16), Text('No lists yet.', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)), const SizedBox(height: 8), Text('Tap the + button to create one!', style: TextStyle(color: Colors.grey.shade500))]))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: _lists.length,
                        itemBuilder: (context, index) {
                          final list = _lists[index];
                          final remainingItems = list.items.where((item) => !item.isChecked).length;

                          return Dismissible(
                            key: Key(list.id.toString()),
                            direction: DismissDirection.endToStart,
                            background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20.0), color: Colors.redAccent, child: const Icon(Icons.delete, color: Colors.white)),
                            confirmDismiss: (direction) async => await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Delete List?'), content: Text('Are you sure you want to delete "${list.name}"?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))])),
                            onDismissed: (direction) => _deleteList(list),
                            child: Card(
                              elevation: 1,
                              margin: const EdgeInsets.symmetric(vertical: 4.0),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: Colors.blue.shade50, child: Icon(_getIconForType(list.type), color: Colors.blue.shade700)),
                                title: Text(list.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                subtitle: Text(list.items.isEmpty ? 'Empty list' : '$remainingItems item(s) remaining'),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ListDetailScreen(
                                        isar: widget.isar,
                                        smartList: list,
                                        syncService: widget.syncService, // PASSED DOWN!
                                      ),
                                    ),
                                  ).then((_) => _loadLists());
                                },
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddListDialog,
        icon: const Icon(Icons.add),
        label: const Text('New List'),
      ),
    );
  }
}