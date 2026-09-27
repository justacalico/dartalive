import 'dart:async';
import 'dart:io';

import '../models/model.dart';
import '../io/media_resolver.dart';
import 'ffmpeg.dart';
import 'graph.dart';

/// Export presets: codec/container/audio combos.
class ExportPreset {
  final String name;
  final String ext;
  final List<String> videoArgs;
  final List<String> audioArgs;
  final String description;
  const ExportPreset(this.name, this.ext, this.videoArgs, this.audioArgs,
      {this.description = ''});

  static const list = [
    ExportPreset(
      'H.264 High (MP4)',
      'mp4',
      ['-c:v', 'libx264', '-preset', 'medium', '-crf', '17', '-pix_fmt', 'yuv420p', '-movflags', '+faststart'],
      ['-c:a', 'aac', '-b:a', '320k'],
      description: 'High quality, plays everywhere',
    ),
    ExportPreset(
      'H.264 Web (MP4)',
      'mp4',
      ['-c:v', 'libx264', '-preset', 'fast', '-crf', '21', '-pix_fmt', 'yuv420p', '-movflags', '+faststart'],
      ['-c:a', 'aac', '-b:a', '192k'],
      description: 'Smaller files for sharing',
    ),
    ExportPreset(
      'HEVC (MP4)',
      'mp4',
      ['-c:v', 'libx265', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p', '-tag:v', 'hvc1'],
      ['-c:a', 'aac', '-b:a', '256k'],
      description: 'H.265, ~half the size of H.264',
    ),
    ExportPreset(
      'VP9 (WebM)',
      'webm',
      ['-c:v', 'libvpx-vp9', '-crf', '30', '-b:v', '0', '-row-mt', '1'],
      ['-c:a', 'libopus', '-b:a', '192k'],
      description: 'Open codec for web',
    ),
    ExportPreset(
      'ProRes 422 (MOV)',
      'mov',
      ['-c:v', 'prores_ks', '-profile:v', '3', '-pix_fmt', 'yuv422p10le'],
      ['-c:a', 'pcm_s16le'],
      description: 'Editing-grade intermediate',
    ),
    ExportPreset(
      'DNxHD 1080p (MOV)',
      'mov',
      ['-c:v', 'dnxhd', '-b:v', '120M', '-pix_fmt', 'yuv422p'],
      ['-c:a', 'pcm_s16le'],
      description: 'Broadcast intermediate',
    ),
    ExportPreset(
      'Audio only (WAV)',
      'wav',
      [],
      ['-c:a', 'pcm_s24le'],
      description: 'Master audio mixdown',
    ),
    ExportPreset(
      'Audio only (MP3)',
      'mp3',
      [],
      ['-c:a', 'libmp3lame', '-b:a', '320k'],
      description: 'Compressed audio',
    ),
    ExportPreset(
      'GIF (small)',
      'gif',
      ['-vf', 'fps=15,scale=640:-2:flags=lanczos', '-loop', '0'],
      ['-an'],
      description: 'Preview gif',
    ),
    ExportPreset(
      'Lossless FFV1 (MKV)',
      'mkv',
      ['-c:v', 'ffv1', '-level', '3', '-pix_fmt', 'yuv420p'],
      ['-c:a', 'flac'],
      description: 'Archival master',
    ),
  ];
}

class ExportJob {
  final String id;
  final String sequenceId;
  final String outputPath;
  final ExportPreset preset;
  final int inFrame, outFrame;
  final int width, height;
  final double fps;
  double progress = 0;
  String status = 'queued'; // queued, running, done, failed, cancelled
  String? error;
  Process? proc;
  ExportJob({
    required this.id,
    required this.sequenceId,
    required this.outputPath,
    required this.preset,
    required this.inFrame,
    required this.outFrame,
    required this.width,
    required this.height,
    required this.fps,
  });
}

class Exporter {
  Project Function() project;
  MediaResolver Function() resolver;
  Exporter(this.project, this.resolver);
  final List<ExportJob> queue = [];
  final _updates = StreamController<void>.broadcast();
  Stream<void> get updates => _updates.stream;
  bool _running = false;

  void enqueue(ExportJob j) {
    queue.add(j);
    _updates.add(null);
    _pump();
  }

  void cancel(String id) {
    final j = queue.where((e) => e.id == id).firstOrNull;
    if (j == null) return;
    if (j.status == 'running') {
      j.proc?.kill();
      j.status = 'cancelled';
    } else if (j.status == 'queued') {
      j.status = 'cancelled';
    }
    _updates.add(null);
  }

  void remove(String id) {
    queue.removeWhere((e) => e.id == id && e.status != 'running');
    _updates.add(null);
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final j = queue.where((e) => e.status == 'queued').firstOrNull;
        if (j == null) break;
        await _run(j);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _run(ExportJob j) async {
    j.status = 'running';
    _updates.add(null);
    try {
      final seq = project().sequenceById(j.sequenceId);
      if (seq == null) throw StateError('sequence missing');
      final gb = GraphBuilder(
          project: project(), resolver: resolver(), width: j.width, height: j.height);
      final g = gb.build(seq, j.inFrame, j.outFrame, audio: true);
      final args = <String>[
        '-hide_banner',
        '-nostdin',
        '-y',
        ...g.inputArgs,
        '-filter_complex', g.filterComplex,
        if (j.preset.videoArgs.isNotEmpty) '-map',
        if (j.preset.videoArgs.isNotEmpty) '[${g.videoLabel}]',
        if (!j.preset.audioArgs.contains('-an')) '-map',
        if (!j.preset.audioArgs.contains('-an')) '[${g.audioLabel}]',
        ...j.preset.videoArgs,
        ...j.preset.audioArgs,
        '-progress', 'pipe:2',
        j.outputPath,
      ];
      final p = await Process.start(FFmpeg.ffmpegPath, args);
      j.proc = p;
      final total = (j.outFrame - j.inFrame) / j.fps;
      final buf = StringBuffer();
      await for (final chunk in p.stderr.transform(const SystemEncoding().decoder)) {
        buf.write(chunk);
        // -progress writes key=value lines
        for (final line in buf.toString().split('\n')) {
          if (line.startsWith('out_time_ms=')) {
            final us = int.tryParse(line.substring(12).trim()) ?? 0;
            j.progress = (us / 1e6 / total).clamp(0.0, 1.0);
            _updates.add(null);
          }
        }
        buf.clear();
      }
      final code = await p.exitCode;
      if (j.status == 'cancelled') {
        // leave as cancelled
      } else if (code == 0) {
        j.status = 'done';
        j.progress = 1;
      } else {
        j.status = 'failed';
        j.error = 'ffmpeg exited $code';
      }
    } catch (e) {
      j.status = 'failed';
      j.error = '$e';
    }
    _updates.add(null);
  }
}

/// Transcode a single media file (bin "transcode" action).
class Transcoder {
  static Future<bool> run(String src, String dst, ExportPreset preset) async {
    final args = <String>[
      '-hide_banner', '-y', '-i', src,
      ...preset.videoArgs.isEmpty ? const ['-vn'] : preset.videoArgs,
      ...preset.audioArgs,
      dst,
    ];
    try {
      final r = await Process.run(FFmpeg.ffmpegPath, args);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
