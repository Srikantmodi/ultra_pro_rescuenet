import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/mesh/mesh_bloc.dart';
import '../bloc/mesh/mesh_state.dart';
import '../widgets/lists/peer_list_tile.dart';
import '../widgets/tactical_background.dart';

/// Main dashboard page with Tactical HUD design.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'RESCUENET ',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  color: AppTheme.textPrimary,
                ),
              ),
              const TextSpan(
                text: '// PRO',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: TacticalBackground(
        child: SafeArea(
          child: BlocBuilder<MeshBloc, MeshState>(
            builder: (context, state) {
              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // Status HUD
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildStatusHud(state),
                    ),
                  ),

                  // Mission Stats
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildMissionStats(state),
                    ),
                  ),

                  // Neighbors Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
                      child: Row(
                        children: [
                          Icon(Icons.radar, size: 16, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'DETECTED TARGETS',
                            style: AppTheme.darkTheme.textTheme.labelSmall,
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              '${state.neighbors.length} ACTIVE',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Neighbors list
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: PeerListTile(node: state.neighbors[index]),
                        );
                      },
                      childCount: state.neighbors.length,
                    ),
                  ),

                  // Empty State
                  if (state.neighbors.isEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        height: 200,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wifi_tethering_off, size: 48, color: AppTheme.textDim.withValues(alpha: 0.3)),
                            const SizedBox(height: 16),
                            Text(
                              'NO TARGETS IN RANGE',
                              style: AppTheme.darkTheme.textTheme.labelSmall?.copyWith(
                                color: AppTheme.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHud(MeshState state) {
    return Row(
      children: [
        Expanded(
          child: _HudCard(
            label: 'LINK STATUS',
            value: state.isActive ? 'ONLINE' : 'OFFLINE',
            icon: state.isActive ? Icons.wifi_tethering : Icons.portable_wifi_off,
            color: state.isActive ? AppTheme.success : AppTheme.textDim,
            isGlowing: state.isActive,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _HudCard(
            label: 'UPLINK',
            value: state.hasInternet ? 'CONNECTED' : 'LOCAL ONLY',
            icon: state.hasInternet ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            color: state.hasInternet ? AppTheme.primary : AppTheme.warning,
            isGlowing: state.hasInternet,
          ),
        ),
      ],
    );
  }

  Widget _buildMissionStats(MeshState state) {
    final stats = state.statistics;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.surfaceHighlight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.data_usage, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text('MISSION TELEMETRY', style: AppTheme.darkTheme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatDigit(label: 'TX PACKETS', value: stats.packetsSent),
              _StatDigit(label: 'RX PACKETS', value: stats.packetsReceived),
              _StatDigit(label: 'RELAYED', value: stats.packetsRelayed),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppTheme.surfaceHighlight),
          const SizedBox(height: 16),
           Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: AppTheme.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'SOS SIGNALS INTERCEPTED',
                  style: TextStyle(
                    color: AppTheme.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Text(
                stats.sosReceived.toString().padLeft(3, '0'),
                style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: 20,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HudCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isGlowing;

  const _HudCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isGlowing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isGlowing ? color.withValues(alpha: 0.5) : AppTheme.surfaceHighlight,
          width: 1,
        ),
        boxShadow: isGlowing ? [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 1
          )
        ] : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
              if (isGlowing)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: color, blurRadius: 6, spreadRadius: 2)
                    ]
                  ),
                )
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: AppTheme.darkTheme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _StatDigit extends StatelessWidget {
  final String label;
  final int value;

  const _StatDigit({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value.toString().padLeft(4, '0'),
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 20,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: AppTheme.textDim,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
