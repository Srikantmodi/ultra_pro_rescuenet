import '../../repositories/mesh_repository.dart';

/// Use case for starting discovery.
class StartDiscoveryUseCase {
  final MeshRepository _repository;

  StartDiscoveryUseCase(this._repository);

  /// Execute the use case.
  Future<void> call() async {
    await _repository.start();
  }
}
