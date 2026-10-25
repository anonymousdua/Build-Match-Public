import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Dashed drop area: drag files from Explorer or click to browse.
class FileDropZone extends StatefulWidget {
  const FileDropZone({
    super.key,
    required this.onFiles,
    required this.extensions,
    required this.title,
    required this.subtitle,
    this.icon = Icons.cloud_upload_outlined,
    this.multiple = true,
    this.height = 140,
    this.enabled = true,
    this.child,
  });

  final ValueChanged<List<PickedFile>> onFiles;
  final List<String> extensions;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool multiple;
  final double height;
  final bool enabled;
  final Widget? child; // replaces the default content (e.g. an image preview)

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _hover = false;

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: widget.extensions,
      allowMultiple: widget.multiple,
      withData: true,
    );
    if (result == null) return;
    final files = <PickedFile>[];
    for (final f in result.files) {
      final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (bytes != null) files.add(PickedFile(f.name, bytes));
    }
    if (files.isNotEmpty) widget.onFiles(files);
  }

  Future<void> _dropped(DropDoneDetails details) async {
    final files = <PickedFile>[];
    for (final f in details.files) {
      files.add(PickedFile(f.name, await f.readAsBytes()));
      if (!widget.multiple) break;
    }
    if (files.isNotEmpty) widget.onFiles(files);
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.child ??
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, size: 30, color: AppColors.primary),
            const SizedBox(height: 10),
            Text(widget.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 3),
            Text(widget.subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        );

    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => setState(() => _hover = true),
      onDragExited: (_) => setState(() => _hover = false),
      onDragDone: (d) {
        setState(() => _hover = false);
        _dropped(d);
      },
      child: InkWell(
        onTap: widget.enabled ? _browse : null,
        borderRadius: BorderRadius.circular(10),
        child: CustomPaint(
          painter: _DashedBorderPainter(color: _hover ? AppColors.primary : AppColors.borderStrong),
          child: Container(
            height: widget.height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: _hover ? AppColors.blueBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => old.color != color;
}
