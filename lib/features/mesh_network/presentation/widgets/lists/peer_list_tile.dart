import 'package:flutter/material.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../domain/entities/node_info.dart';

/// List tile for displaying peer/neighbor information with HUD styling.
class PeerListTile extends StatelessWidget {
  final NodeInfo node;
  final bool isSelected;
  final bool isBestRoute;
  final VoidCallback? onTap;

  const PeerListTile({
    super.key,
    required this.node,
    this.isSelected = false,
    this.isBestRoute = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // HUD Card Styling
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected 
            ? AppTheme.primary 
            : isBestRoute 
              ? AppTheme.success.withValues(alpha: 0.5) 
              : AppTheme.surfaceHighlight,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Node avatar (Target Identifier)
                _buildAvatar(),
                const SizedBox(width: 16),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name and badges
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              node.displayName.isNotEmpty
                                  ? node.displayName.toUpperCase()
                                  : 'NODE-${node.id.substring(0, 4).toUpperCase()}',
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (node.hasInternet) _buildBadge(Icons.cloud, AppTheme.primary, 'NET'),
                          if (isBestRoute) _buildBadge(Icons.star, AppTheme.warning, 'BEST'),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Status row (Metrics)
                      Row(
                        children: [
                          // Battery
                          _buildMetric(
                            Icons.battery_std,
                            '${node.batteryLevel}%',
                            _getBatteryColor(node.batteryLevel),
                          ),
                          const SizedBox(width: 12),

                          // Signal
                          _buildMetric(
                            Icons.signal_cellular_alt,
                            '${node.signalStrength}dB',
                            _getSignalColor(node.signalStrength),
                          ),
                          const SizedBox(width: 12),

                          // Location indicator
                          if (node.latitude != 0 && node.longitude != 0)
                            _buildMetric(
                              Icons.my_location,
                              'GPS',
                              AppTheme.textSecondary,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Triage status
                if (node.triageLevel != NodeInfo.triageNone) 
                  _buildTriageIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    Color borderColor;
    
    switch (node.triageLevel) {
      case NodeInfo.triageRed:
        borderColor = AppTheme.danger;
        break;
      case NodeInfo.triageYellow:
        borderColor = AppTheme.warning;
        break;
      default:
        borderColor = node.hasInternet ? AppTheme.primary : AppTheme.textDim;
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.background,
        border: Border.all(color: borderColor, width: 2),
        shape: BoxShape.rectangle, // Square targeting reticle style
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          node.displayName.isNotEmpty
              ? node.displayName[0].toUpperCase()
              : node.id.substring(0, 2).toUpperCase(),
          style: TextStyle(
            color: borderColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(IconData icon, Color color, String text) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMetric(IconData icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: color, 
            fontSize: 12,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500
          ),
        ),
      ],
    );
  }

  Widget _buildTriageIndicator() {
    IconData icon;
    Color color;
    
    switch (node.triageLevel) {
      case NodeInfo.triageRed:
        icon = Icons.warning_rounded;
        color = AppTheme.danger;
        break;
      case NodeInfo.triageYellow:
        icon = Icons.info_outline;
        color = AppTheme.warning;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Color _getBatteryColor(int level) => level > 30 ? AppTheme.success : AppTheme.danger;
  Color _getSignalColor(int strength) => strength > -70 ? AppTheme.success : AppTheme.warning;
}
