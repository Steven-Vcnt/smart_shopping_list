import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Make sure this is imported!
import 'firebase_options.dart';
import 'models/database_models.dart';
import 'home_screen.dart';
import 'sync_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'auth_screen.dart'; // YOUR NEW SCREEN

Future<void> signInWithGoogle() async {
  try {
    final googleSignIn = GoogleSignIn.instance;
    
    // 1. Initialize the plugin with your Web Client ID as the serverClientId
    await googleSignIn.initialize(
      serverClientId: '907777869327-lj36roie54i54u2l26sddoels8t3unbu.apps.googleusercontent.com',
    );

    await googleSignIn.signOut();
    await FirebaseAuth.instance.signOut();

    // 2. Trigger the native Google Account popup
    final GoogleSignInAccount? googleUser = await googleSignIn.authenticate();
    
    if (googleUser == null) {
      debugPrint("User canceled the sign-in.");
      return;
    }

    // 3. Request permissions to get the Access Token
    final clientAuth = await googleUser.authorizationClient?.authorizeScopes(['email', 'profile']);
    
    // 4. Fetch the authentication details (This now securely contains the idToken!)
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

    // 5. Create the credential using BOTH tokens
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: clientAuth?.accessToken,
      idToken: googleAuth.idToken, // This will no longer be null!
    );

    // 6. Sign in to Firebase Production safely
    final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
    
    debugPrint("✅ Google Sign-In Success! Welcome, ${userCredential.user?.email}");
  } catch (e) {
    debugPrint("❌ Google Sign-In Error: $e");
  }
}

//// 1. Here is the declaration of the function
Future<void> initializeProductionAuth() async {
  try {
    final userCredential = await FirebaseAuth.instance.signInAnonymously();
    debugPrint("Authenticated securely in production with UID: ${userCredential.user?.uid}");
  } catch (e) {
    debugPrint("Auth Error: $e");
  }
}
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // We REMOVED the forced signInWithGoogle() from here!

  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [SmartListSchema, MasterProductSchema, UserShopSchema],
    directory: dir.path,
  );

  final syncService = SyncService(isar);
  runApp(MyApp(isar: isar, syncService: syncService));
}

class MyApp extends StatelessWidget {
  final Isar isar;
  final SyncService syncService;

  const MyApp({super.key, required this.isar, required this.syncService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Lists',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0, backgroundColor: Colors.transparent),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(16)),
        ),
      ),
      // THE MAGIC ROUTER
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // If Firebase is still figuring out if you are logged in...
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          
          // If we have a logged-in user (Google OR Guest)
          if (snapshot.hasData && snapshot.data != null) {
            return HomeScreen(isar: isar, syncService: syncService);
          }
          
          // If we have no user, show the beautiful login page!
          return const AuthScreen();
        },
      ),
    );
  }
}