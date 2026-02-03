import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/mesh_repository_impl.dart';
import 'transmission_event.dart';
import 'transmission_state.dart';

/// BLoC for managing packet transmission.
class TransmissionBloc extends Bloc<TransmissionEvent, TransmissionState> {
  final MeshRepositoryImpl _repository;

  TransmissionBloc({required MeshRepositoryImpl repository})
      : _repository = repository,
        super(const TransmissionState()) {
    on<SendPacket>(_onSendPacket);
    on<PacketSent>(_onPacketSent);
    on<PacketFailed>(_onPacketFailed);
    on<ClearTransmissionHistory>(_onClear);
  }

  Future<void> _onSendPacket(
    SendPacket event,
    Emitter<TransmissionState> emit,
  ) async {
    emit(state.copyWith(
      isSending: true,
      currentPacketId: event.packet.id,
      error: null,
    ));

    try {
      final success = await _repository.sendPacket(event.packet);

      if (success) {
        add(PacketSent(event.packet.id, ''));
      } else {
        add(PacketFailed(event.packet.id, 'Transmission failed'));
      }
    } catch (e) {
      add(PacketFailed(event.packet.id, e.toString()));
    }
  }

  Future<void> _onPacketSent(
    PacketSent event,
    Emitter<TransmissionState> emit,
  ) async {
    final record = TransmissionRecord(
      packetId: event.packetId,
      targetNodeId: event.targetNodeId,
      success: true,
      timestamp: DateTime.now(),
    );

    emit(state.copyWith(
      isSending: false,
      history: [record, ...state.history].take(100).toList(),
      currentPacketId: null,
    ));
  }

  Future<void> _onPacketFailed(
    PacketFailed event,
    Emitter<TransmissionState> emit,
  ) async {
    final record = TransmissionRecord(
      packetId: event.packetId,
      success: false,
      timestamp: DateTime.now(),
      error: event.error,
    );

    emit(state.copyWith(
      isSending: false,
      history: [record, ...state.history].take(100).toList(),
      currentPacketId: null,
      error: event.error,
    ));
  }

  Future<void> _onClear(
    ClearTransmissionHistory event,
    Emitter<TransmissionState> emit,
  ) async {
    emit(state.copyWith(history: []));
  }
}
