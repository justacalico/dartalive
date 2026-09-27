import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Binary discovery + ffprobe + thumbnail/waveform/proxy helpers.
class FFmpeg {
  static String ffmpegPath = 'ffmpeg';
  static String ffprobePath = 'ffprobe';

  static Future<bool> available() async {
    try {
      final r = await Process.run(ffmpegPath, ['-version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> version() async {
    try {
      final r = await Process.run(ffmpegPath, ['-version']);
      final out = '${r.stdout}'.split('\n').first;
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Probe a media file. Returns a map mirroring ffprobe -show_format/-show_streams.
  static Future<Map<String, dynamic>?> probe(String path) async {
    try {
      final r = await Process.run(ffprobePath, [
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_format',
        '-show_streams',
        path,
      ]);
      if (r.exitCode != 0) return null;
      return jsonDecode('${r.stdout}') as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Convenience: structured media info from probe output.
  static MediaProbe? parseProbe(Map<String, dynamic> j) {
    try {
      final fmt = j['format'] as Map<String, dynamic>? ?? {};
      final streams = (j['streams'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final v = streams.where((s) => s['codec_type'] == 'video').firstOrNull;
      final a = streams.where((s) => s['codec_type'] == 'audio').firstOrNull;
      double fps = 0;
      if (v != null) {
        final r = '${v['avg_frame_rate'] ?? v['r_frame_rate'] ?? '0/1'}';
        final parts = r.split('/');
        if (parts.length == 2) {
          final n = double.tryParse(parts[0]) ?? 0;
          final d = double.tryParse(parts[1]) ?? 1;
          if (d != 0) fps = n / d;
        }
      }
      return MediaProbe(
        duration: double.tryParse('${fmt['duration'] ?? ''}') ??
            double.tryParse('${v?['duration'] ?? ''}') ??
            double.tryParse('${a?['duration'] ?? ''}') ??
            0,
        width: v?['width'] as int? ?? 0,
        height: v?['height'] as int? ?? 0,
        fps: fps,
        hasVideo: v != null,
        hasAudio: a != null,
        sampleRate: int.tryParse('${a?['sample_rate'] ?? ''}') ?? 0,
        channels: a?['channels'] as int? ?? 0,
        codec: '${v?['codec_name'] ?? a?['codec_name'] ?? ''}',
        bitRate: int.tryParse('${fmt['bit_rate'] ?? ''}') ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Extract a JPEG thumbnail at [sec], scaled to [width] max.
  /// Returns raw jpeg bytes or null.
  static Future<List<int>?> thumbnail(String path, double sec, int width) async {
    try {
      final p = await Process.start(ffmpegPath, [
        '-ss', sec.toStringAsFixed(3),
        '-i', path,
        '-frames:v', '1',
        '-vf', 'scale=$width:-2',
        '-f', 'image2pipe',
        '-vcodec', 'mjpeg',
        '-q:v', '5',
        '-',
      ]);
      final buf = await _collectStdout(p, timeout: const Duration(seconds: 15));
      if (buf.isEmpty) return null;
      return buf;
    } catch (_) {
      return null;
    }
  }

  /// Waveform peaks: decode audio, return per-bucket min/max for [buckets].
  /// Values in [-1, 1]. Mono-fold.
  static Future<List<double>?> waveform(String path,
      {int buckets = 2000}) async {
    try {
      final p = await Process.start(ffmpegPath, [
        '-i', path,
        '-vn',
        '-ac', '1',
        '-ar', '8000',
        '-f', 's16le',
        '-',
      ]);
      final bytes = await _collectStdout(p, timeout: const Duration(minutes: 3));
      if (bytes.length < 2) return null;
      final total = bytes.length ~/ 2;
      final peaks = List<double>.filled(buckets * 2, 0);
      final per = total / buckets;
      for (var i = 0; i < total; i++) {
        final b = i ~/ per;
        if (b >= buckets) break;
        final s = (bytes[i * 2] | (bytes[i * 2 + 1] << 8)).toSigned(16) / 32768.0;
        if (s < peaks[b * 2]) peaks[b * 2] = s;
        if (s > peaks[b * 2 + 1]) peaks[b * 2 + 1] = s;
      }
      return peaks;
    } catch (_) {
      return null;
    }
  }

  /// Generate a lightweight editing proxy next to the project cache.
  static Future<bool> proxy(String src, String dst, {int width = 960}) async {
    try {
      final r = await Process.run(ffmpegPath, [
        '-y', '-i', src,
        '-vf', 'scale=$width:-2',
        '-c:v', 'mpeg4', '-q:v', '5',
        '-c:a', 'aac', '-b:a', '96k',
        dst,
      ]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<List<int>> _collectStdout(Process p,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final buf = BytesBuilder(copy: false);
    final done = Completer<void>();
    p.stdout.listen(buf.add, onDone: done.complete, onError: (_) => done.complete());
    p.stderr.drain<void>();
    await done.future.timeout(timeout, onTimeout: () {
      p.kill();
    });
    return buf.takeBytes();
  }
}

class MediaProbe {
  final double duration;
  final int width, height;
  final double fps;
  final bool hasVideo, hasAudio;
  final int sampleRate, channels;
  final String codec;
  final int bitRate;
  const MediaProbe({
    required this.duration,
    required this.width,
    required this.height,
    required this.fps,
    required this.hasVideo,
    required this.hasAudio,
    required this.sampleRate,
    required this.channels,
    required this.codec,
    required this.bitRate,
  });
}
