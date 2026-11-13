import 'package:flutter/material.dart';
import 'package:renombrata/src/models/renombrata_project.dart';

/// A sleek top header guide for the Convention Editor displaying:
/// 1. Active Camera badge + clip name + active line number.
/// 2. Sequence breadcrumb showing the exact order of convention tokens.
class ConventionSequenceGuide extends StatelessWidget {
  final CameraType cameraType;
  final bool isDrivingShot;
  final bool isGoPro;
  final String? activeCamera;
  final String? activeClipName;
  final int? activeLineNumber;
  final String? currentLineText;

  const ConventionSequenceGuide({
    super.key,
    this.cameraType = CameraType.regular,
    this.isDrivingShot = false,
    this.isGoPro = false,
    this.activeCamera,
    this.activeClipName,
    this.activeLineNumber,
    this.currentLineText,
  });

  static Color getCameraColor(String? cam) {
    if (cam == null || cam.isEmpty) return const Color(0xFF64748B);
    final upper = cam.toUpperCase();
    if (upper == 'A' || upper.startsWith('A')) return const Color(0xFF26A69A); // Teal
    if (upper == 'B' || upper.startsWith('B')) return const Color(0xFFFFA726); // Amber
    if (upper == 'C' || upper.startsWith('C')) return const Color(0xFFAB47BC); // Purple
    if (upper.startsWith('GPR') || upper.startsWith('GP')) return const Color(0xFF00E676); // Green
    if (upper.startsWith('DR')) return const Color(0xFF29B6F6); // Sky
    if (upper.startsWith('DS')) return const Color(0xFFFF7043); // Coral
    return const Color(0xFF42A5F5); // Blue fallback
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveIsGpr = isGoPro || cameraType == CameraType.goPro;
    final effectiveIsDs = isDrivingShot || cameraType == CameraType.drivingShot;

    // Tokens definition based on camera type
    final tokens = <_GuideToken>[
      const _GuideToken(label: 'PROD', tooltip: 'Nomenclatura del proyecto (ej. MNBOENC)'),
      _GuideToken(
        label: effectiveIsGpr || effectiveIsDs ? 'FECHA' : 'CAP/FECHA',
        tooltip: 'Capítulo o Fecha de rodaje (ej. 080626 o 101)',
      ),
      const _GuideToken(label: 'ESC', tooltip: 'Número de escena (ej. 17)'),
      const _GuideToken(label: 'PLANO*', tooltip: 'Plano o encuadre opcional (ej. P1)', isOptional: true),
      const _GuideToken(label: 'TOMA', tooltip: 'Número de toma (ej. T1, TF1)'),
      _GuideToken(
        label: effectiveIsGpr ? 'GPR/TARJ' : (effectiveIsDs ? 'TARJ' : 'REEL'),
        tooltip: effectiveIsGpr ? 'GPR1 o Tarjeta GoPro' : 'Rollo de cámara (ej. A001, B002)',
      ),
      const _GuideToken(label: 'CLIP', tooltip: 'Índice de clip (ej. 01, 1)'),
      const _GuideToken(label: 'DÍA', tooltip: 'Día de llamado (ej. D1)'),
      _GuideToken(
        label: effectiveIsDs ? 'DS' : 'UNIDAD',
        tooltip: effectiveIsDs ? 'Driving Shot (DS)' : 'Unidad de grabación (ej. U1, U2)',
      ),
      _GuideToken(
        label: '% METADATOS',
        tooltip: 'Metadatos proforma post-% (TARJ_CLIP_DIA_UCR) [Protegido/Atenuado]',
        isMetadata: true,
      ),
    ];

    final camColor = getCameraColor(activeCamera);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Context Row: Camera badge + Active Line & Clip
          if (activeCamera != null || activeClipName != null || activeLineNumber != null) ...[
            Row(
              children: [
                if (activeCamera != null) ...[
                  Container(
                    key: const ValueKey('convention_guide_camera_badge'),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: camColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: camColor, width: 1),
                    ),
                    child: Text(
                      'CAM $activeCamera',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: camColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (activeLineNumber != null) ...[
                  Text(
                    'Línea $activeLineNumber',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (activeClipName != null) ...[
                  Expanded(
                    child: Text(
                      '➔ $activeClipName',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        color: theme.hintColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
          ],

          // 2. Token Sequence Breadcrumb
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < tokens.length; i++) ...[
                  Tooltip(
                    message: tokens[i].tooltip,
                    child: Container(
                      key: ValueKey('guide_token_${tokens[i].label}'),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: tokens[i].isMetadata
                            ? (isDark ? Colors.white10 : Colors.black12)
                            : (isDark ? const Color(0xFF22222A) : Colors.white),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: tokens[i].isMetadata
                              ? (isDark ? const Color(0xFF3F3F46) : const Color(0xFFCBD5E1))
                              : theme.dividerColor.withValues(alpha: 0.2),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        tokens[i].label,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          fontWeight: tokens[i].isMetadata ? FontWeight.w500 : FontWeight.bold,
                          color: tokens[i].isMetadata
                              ? (isDark ? const Color(0xFF8E8E9F) : const Color(0xFF64748B))
                              : (tokens[i].isOptional ? theme.hintColor : theme.colorScheme.onSurface),
                          fontStyle: tokens[i].isMetadata ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                    ),
                  ),
                  if (i < tokens.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      child: Text(
                        tokens[i + 1].isMetadata ? ' % ' : ' _ ',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: tokens[i + 1].isMetadata
                              ? (isDark ? const Color(0xFF8E8E9F) : const Color(0xFF64748B))
                              : theme.hintColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideToken {
  final String label;
  final String tooltip;
  final bool isOptional;
  final bool isMetadata;

  const _GuideToken({
    required this.label,
    required this.tooltip,
    this.isOptional = false,
    this.isMetadata = false,
  });
}

