import 'package:cloud_functions/cloud_functions.dart';

class FirebaseWeddingService {
  FirebaseWeddingService()
      : _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> _call(
    String name, [
    Map<String, dynamic> data = const {},
  ]) async {
    final result = await _functions.httpsCallable(name).call(data);
    final value = result.data;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw StateError('Firebase returned an invalid response for ' + name + '.');
  }

  Future<Map<String, dynamic>> bootstrapCustomer() =>
      _call('bootstrapCustomer');

  Future<Map<String, dynamic>> prepareWeddingUpload() =>
      _call('prepareWeddingUpload');

  Future<Map<String, dynamic>> getAccountState() =>
      _call('getWeddingAccountState');

  Future<Map<String, dynamic>> setAutoDeleteConsent({
    required String videoId,
    required bool consent,
  }) =>
      _call('setAutoDeleteConsent', {
        'videoId': videoId,
        'consent': consent,
      });

  Future<Map<String, dynamic>> createRazorpayOrder() =>
      _call('createRazorpayOrder');

  Future<Map<String, dynamic>> verifyRazorpayPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) =>
      _call('verifyRazorpayPayment', {
        'razorpayOrderId': razorpayOrderId,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpaySignature': razorpaySignature,
      });

  Future<Map<String, dynamic>> createWeddingShare() =>
      _call('createWeddingShare');
}
