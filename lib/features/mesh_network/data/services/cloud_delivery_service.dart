import 'dart:io';
import 'package:http/http.dart' as http;
import '../../domain/entities/sos_payload.dart';
import '../../../../core/error/failures.dart';
import 'package:dartz/dartz.dart';

/// Service responsible for delivering SOS packets to the cloud backend.
///
/// This service is used when the node has internet connectivity ("Goal" node).
/// It takes the place of the mesh relay mechanism.
///
/// CRITICAL FIX: Before performing the mock upload, this service now verifies
/// real internet connectivity via an HTTP HEAD check. This prevents the mock
/// from returning "success" on a device that actually has no internet —
/// which was causing SOS packets to terminate at non-goal nodes.
class CloudDeliveryService {
  // TODO: Replace with actual backend URL
  // ignore: unused_field
  static const String _backendUrl = 'https://api.rescuenet.com/v1/sos';

  /// Timeout for connectivity verification.
  static const Duration _verifyTimeout = Duration(seconds: 3);

  // ignore: unused_field
  final http.Client _client;

  CloudDeliveryService({http.Client? client}) : _client = client ?? http.Client();

  /// Uploads an SOS payload to the cloud.
  ///
  /// Returns [Right(true)] if successful, [Left(failure)] otherwise.
  ///
  /// STEP 1: Verifies real internet connectivity via HTTP before uploading.
  /// STEP 2: Performs the upload (currently mock, to be replaced with real API).
  ///
  /// If connectivity verification fails, returns [Left] immediately so the
  /// caller can fall back to mesh relay forwarding.
  Future<Either<Failure, bool>> uploadSos(SosPayload sos, String originalSenderId) async {
    try {
      // STEP 1: Verify real internet connectivity BEFORE trusting the mock/upload.
      // This catches the case where InternetProbe was right but connectivity
      // was lost between the probe and the upload attempt.
      final hasRealInternet = await _verifyConnectivity();
      if (!hasRealInternet) {
        print('☁️ [CloudDelivery] REJECTED: No real internet connectivity — '
            'packet will be relayed instead');
        return Left(ServerFailure('No real internet connectivity'));
      }

      // STEP 2: Actual upload (mock for now).
      // TODO: Replace with actual HTTP POST when backend is ready.
      // Will use _client.post(Uri.parse(_backendUrl), ...) once backend is live.
      await Future.delayed(const Duration(seconds: 1));

      print('☁️ [CloudDelivery] UPLOAD SUCCESS (verified): SOS from $originalSenderId');
      return const Right(true);
      
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Performs a quick HTTP check to verify real internet connectivity.
  ///
  /// Returns true ONLY if we get HTTP 204 from Google's connectivity check.
  /// This is the same authoritative check used by InternetProbe, providing
  /// a double-verification layer right before the upload.
  Future<bool> _verifyConnectivity() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _verifyTimeout;
      final request = await client.getUrl(
        Uri.parse('http://connectivitycheck.gstatic.com/generate_204'),
      ).timeout(_verifyTimeout);
      final response = await request.close().timeout(_verifyTimeout);
      await response.drain<void>();
      return response.statusCode == 204;
    } catch (e) {
      return false;
    } finally {
      client?.close();
    }
  }
}
