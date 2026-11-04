import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseBackend {
  FirebaseBackend._();

  static final FirebaseAuth auth = FirebaseAuth.instance;
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;

  static User? get currentUser => auth.currentUser;

  static Future<User> signInAnonymouslyIfNeeded() async {
    final current = auth.currentUser;
    final user = current ?? (await auth.signInAnonymously()).user;
    if (user == null) throw StateError('Firebase did not create a customer session.');
    await _saveCustomerProfile(user);
    return user;
  }

  static Future<UserCredential> linkCurrentAccountWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final credential = EmailAuthProvider.credential(
      email: normalizedEmail,
      password: password,
    );
    final current = auth.currentUser;
    if (current == null) {
      final result = await auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      if (result.user != null) await _saveCustomerProfile(result.user!);
      return result;
    }
    if (current.email?.toLowerCase() == normalizedEmail && !current.isAnonymous) {
      await _saveCustomerProfile(current);
      return UserCredential._(current);
    }
    try {
      final result = await current.linkWithCredential(credential);
      if (result.user != null) await _saveCustomerProfile(result.user!);
      return result;
    } on FirebaseAuthException catch (error) {
      if (error.code != 'credential-already-in-use') rethrow;
      final result = await auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      if (result.user != null) await _saveCustomerProfile(result.user!);
      return result;
    }
  }

  static Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final result = await auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    if (result.user != null) await _saveCustomerProfile(result.user!);
    return result;
  }

  static Future<void> _saveCustomerProfile(User user) async {
    await firestore.collection('customers').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'updatedAt': FieldValue.serverTimestamp(),
      if (!user.metadata.creationTime!.isBefore(DateTime.now().subtract(const Duration(seconds: 10))))
        'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> signOut() => auth.signOut();
}
