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

  static Future<User> linkCurrentAccountWithEmailPassword({
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
      return result.user!;
    }
    if (current.email?.toLowerCase() == normalizedEmail && !current.isAnonymous) {
      await _saveCustomerProfile(current);
      return current;
    }
    try {
      final result = await current.linkWithCredential(credential);
      if (result.user != null) await _saveCustomerProfile(result.user!);
      return result.user!;
    } on FirebaseAuthException catch (error) {
      if (error.code != 'credential-already-in-use') rethrow;
      final result = await auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      if (result.user != null) await _saveCustomerProfile(result.user!);
      return result.user!;
    }
  }

  static Future<User> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final result = await auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    if (result.user == null) throw StateError('Firebase sign-in did not return a user.');
    await _saveCustomerProfile(result.user!);
    return result.user!;
  }

  static Future<void> _saveCustomerProfile(User user) async {
    final ref = firestore.collection('customers').doc(user.uid);
    final existing = await ref.get();
    await ref.set({
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'updatedAt': FieldValue.serverTimestamp(),
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> signOut() => auth.signOut();
}
