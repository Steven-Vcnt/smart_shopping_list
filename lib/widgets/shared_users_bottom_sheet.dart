import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/database_models.dart';

class SharedUsersBottomSheet extends StatefulWidget {
  final SmartList currentList;
  final Function(SmartList) onListUpdated;

  const SharedUsersBottomSheet({
    super.key,
    required this.currentList,
    required this.onListUpdated,
  });

  @override
  State<SharedUsersBottomSheet> createState() => _SharedUsersBottomSheetState();
}

class _SharedUsersBottomSheetState extends State<SharedUsersBottomSheet> {
  final TextEditingController _emailController = TextEditingController();

  void _shareList() {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isNotEmpty && email.contains('@')) {
      if (!widget.currentList.sharedWith.contains(email)) {
        setState(() {
          widget.currentList.sharedWith = List<String>.from(widget.currentList.sharedWith)..add(email);
        });
        widget.onListUpdated(widget.currentList);
      }
      
      _emailController.clear();
      
      Share.share(
        'Hey! I just shared the "${widget.currentList.name}" list with you on Smart Grocery. Open the app to see it!',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerEmail = widget.currentList.ownerEmail;
    final sharedWith = widget.currentList.sharedWith;

    return Padding(
      // Padding to account for keyboard
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Shared Users',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
          // Owner
          if (ownerEmail != null && ownerEmail.isNotEmpty)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade100,
                child: Text(
                  ownerEmail[0].toUpperCase(),
                  style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(ownerEmail),
              subtitle: const Text('Owner'),
            ),
            
          // Shared Users
          if (sharedWith.isNotEmpty) ...[
            const Divider(),
            ...sharedWith.map((email) => ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey.shade200,
                child: Text(
                  email[0].toUpperCase(),
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(email),
              subtitle: const Text('Can edit'),
            )),
          ],

          const SizedBox(height: 16),
          const Text('Invite someone new:'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Google Email Address',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.email),
                  ),
                  onSubmitted: (_) => _shareList(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _shareList,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                ),
                child: const Text('Invite'),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
