import 'package:http/http.dart' as http;
import '../../domain/entities/sos_payload.dart';
import '../../../../core/error/failures.dart';
import 'package:dartz/dartz.dart';

/// Service responsible for delivering SOS packets to the cloud backend.
///
/// This service is used when the node has internet connectivity ("Goal" node).
/// It takes the place of the mesh relay mechanism.
class CloudDeliveryService {
  // TODO: Replace with actual backend URL
  // ignore: unused_field
  static const String _backendUrl = 'https://api.rescuenet.com/v1/sos';

  // ignore: unused_field
  final http.Client _client;

  CloudDeliveryService({http.Client? client}) : _client = client ?? http.Client();

  /// Uploads an SOS payload to the cloud.
  ///
  /// Returns [true] if successful, [false] otherwise.
  Future<Either<Failure, bool>> uploadSos(SosPayload sos, String originalSenderId) async {
    try {
      // TODO: Replace mock with actual HTTP POST when backend is ready.
      // Will use _client.post(Uri.parse(_backendUrl), ...) once backend is live.
      await Future.delayed(const Duration(seconds: 2));

      // Mock success for demonstration
      print('☁️ [CloudDelivery] MOCK UPLOAD SUCCESS: SOS from $originalSenderId');
      return const Right(true);
      
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
