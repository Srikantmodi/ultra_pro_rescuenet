import '../../entities/node_info.dart';
import '../../repositories/mesh_repository.dart';

/// Use case for updating node metadata.
class UpdateMetadataUseCase {
  final MeshRepository _repository;

  UpdateMetadataUseCase(this._repository);

  /// Execute the use case.
  Future<void> call(NodeInfo nodeInfo) async {
    await _repository.updateMetadata(nodeInfo);
  }
}
