import 'package:flutter/material.dart';

import '../core/models.dart';

class EtaBadge extends StatelessWidget {
  const EtaBadge({
    required this.stop,
    required this.alwaysShowSeconds,
    super.key,
  });

  final StopInfo stop;
  final bool alwaysShowSeconds;

  @override
  Widget build(BuildContext context) {
    final eta = buildEtaPresentation(
      stop,
      alwaysShowSeconds: alwaysShowSeconds,
    );

    return Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: eta.backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        eta.text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: eta.foregroundColor,
          fontWeight: FontWeight.w700,
          fontSize: eta.text.contains('\n') ? 12 : 14,
          height: 1.1,
        ),
      ),
    );
  }
}
