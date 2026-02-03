import '../../repositories/mesh_repository.dart';

/// Use case for stopping discovery.
class StopDiscoveryUseCase {
  final MeshRepository _repository;

  StopDiscoveryUseCase(this._repository);

  /// Execute the use case.
  Future<void> call() async {
    await _repository.stop();
  }
}
