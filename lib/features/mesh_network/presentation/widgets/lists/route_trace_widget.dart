import 'package:flutter/material.dart';

/// Widget showing packet route trace.
class RouteTraceWidget extends StatelessWidget {
  final List<String> trace;
  final String? currentNodeId;

  const RouteTraceWidget({
    super.key,
    required this.trace,
    this.currentNodeId,
  });

  @override
  Widget build(BuildContext context) {
    if (trace.isEmpty) {
      return const Center(
        child: Text(
          'No trace data',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Packet Route',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        ...trace.asMap().entries.map((entry) {
          final index = entry.key;
          final nodeId = entry.value;
          final isCurrentNode = nodeId == currentNodeId;
          final isFirst = index == 0;
          final isLast = index == trace.length - 1;

          return _TraceNode(
            nodeId: nodeId,
            hopNumber: index + 1,
            isFirst: isFirst,
            isLast: isLast,
            isCurrentNode: isCurrentNode,
          );
        }),
      ],
    );
  }
}

class _TraceNode extends StatelessWidget {
  final String nodeId;
  final int hopNumber;
  final bool isFirst;
  final bool isLast;
  final bool isCurrentNode;

  const _TraceNode({
    required this.nodeId,
    required this.hopNumber,
    required this.isFirst,
    required this.isLast,
    required this.isCurrentNode,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Connector line
        SizedBox(
          width: 32,
          child: Column(
            children: [
              if (!isFirst)
                Container(
                  width: 2,
                  height: 12,
                  color: Colors.cyan.withAlpha(100),
                ),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrentNode ? Colors.green : Colors.cyan,
                  boxShadow: isCurrentNode
                      ? [
                          BoxShadow(
                            color: Colors.green.withAlpha(100),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 12,
                  color: Colors.cyan.withAlpha(100),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // Node info
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isCurrentNode
                  ? Colors.green.withAlpha(30)
                  : const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(8),
              border: isCurrentNode
                  ? Border.all(color: Colors.green.withAlpha(100))
                  : null,
            ),
            child: Row(
              children: [
                Text(
                  'Hop $hopNumber',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    nodeId.length > 12
                        ? '${nodeId.substring(0, 12)}...'
                        : nodeId,
                    style: TextStyle(
                      color: isCurrentNode ? Colors.green : Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                if (isFirst)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(50),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ORIGIN',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (isCurrentNode)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(50),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'YOU',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
