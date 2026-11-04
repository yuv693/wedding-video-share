import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseBackend {
  FirebaseBackend._();

  static final FirebaseAuth auth = FirebaseAuth.instance;
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static final FirebaseFunctions functions = FirebaseFunctions.instance;

  static User? get currentUser => auth.currentUser;

  static Future<User> signInAnonymouslyIfNeeded() async {
    final current = auth.currentUser;
    if (current != null) {
      await bootstrapCustomer();
      return current;
    }
    final result = await auth.signInAnonymously();
    final user = result.user;
    if (user == null) throw StateError('Firebase did not create a customer session.');
    await bootstrapCustomer();
    return user;
  }

  static Future<void> bootstrapCustomer() async {
    await functions.httpsCallable('bootstrapCustomer').call<void>();
  }

  static Future<Map<String, dynamic>> getAccountState() async {
    final result = await functions.httpsCallable('getWeddingAccountState').call<Map>();
    return Map<String, dynamic>.from(result.data);
  }

  static Future<String> prepareWeddingUpload() async {
    final result = await functions.httpsCallable('prepareWeddingUpload').call<Map>();
    final data = Map<String, dynamic>.from(result.data);
    final orderId = data['orderId']?.toString();
    if (data['ok'] != true || orderId == null || orderId.isEmpty) {
      throw StateError('Could not prepare the wedding upload.');
    }
    return orderId;
  }

  static Future<void> setAutoDeleteConsent({
    required String videoId,
    required bool consent,
  }) async {
    await functions.httpsCallable('setAutoDeleteConsent').call<void>({
      'videoId': videoId,
      'consent': consent,
    });
  }

  static Future<void> signOut() => auth.signOut();
}
