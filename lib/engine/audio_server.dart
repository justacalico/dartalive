import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../models/model.dart';
import '../io/media_resolver.dart';
import 'ffmpeg.dart';
import 'graph.dart';

/// Streams timeline audio to the media_kit player over a loopback HTTP
/// server. FFmpeg renders WAV; Dart proxies it. Seeking restarts the render
/// and re-opens the player stream.
class AudioServer {
  Project Function() project;
  MediaResolver Function() resolver;

  HttpServer? _server;
  int _port = 0;
  Process? _proc;
  final _buffer = BytesBuilder();
  bool _done = false;
  int _gen = 0;
  bool _serving = false;

  AudioServer(this.project, this.resolver);

  Future<int> _ensureServer() async {
    if (_server != null) return _port;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen((req) async {
      if (_serving) {
        req.response.statusCode = 409;
        await req.response.close();
        return;
      }
      _serving = true;
      req.response.headers.contentType = ContentType('audio', 'wav');
      req.response.headers.chunkedTransferEncoding = true;
      final gen = _gen;
      try {
        while (gen == _gen) {
          final data = _buffer.takeBytes();
          if (data.isNotEmpty) {
            req.response.add(data);
          } else if (_done) {
            break;
          } else {
            await Future.delayed(const Duration(milliseconds: 8));
          }
        }
      } catch (_) {}
      _serving = false;
      try {
        await req.response.close();
      } catch (_) {}
    });
    return _port;
  }

  String? _currentUrl;

  /// Begin rendering audio of [seq] from [startFrame]; returns stream URL.
  Future<String> start(Sequence seq, int startFrame) async {
    _gen++;
    _proc?.kill();
    _buffer.takeBytes();
    _done = false;
    await _ensureServer();

    final end = seq.duration;
    if (end <= startFrame) {
      _done = true;
      _currentUrl = null;
      return '';
    }
    final gb = GraphBuilder(project: project(), resolver: resolver());
    final g = gb.build(seq, startFrame, end, audio: true, video: false);
    if (g.audioLabel.isEmpty) {
      _done = true;
      _currentUrl = null;
      return '';
    }
    final args = <String>[
      '-hide_banner', '-loglevel', 'error',
      ...g.inputArgs,
      '-filter_complex', g.filterComplex,
      '-map', '[${g.audioLabel}]',
      '-f', 'wav',
      '-ac', '2',
      '-ar', '${project().sampleRate}',
      '-',
    ];
    final gen = _gen;
    _proc = await Process.start(FFmpeg.ffmpegPath, args);
    if (gen != _gen) {
      _proc!.kill();
      return '';
    }
    _proc!.stdout.listen((c) {
      _buffer.add(c);
      // cap buffered audio ~16MB — consumer never falls far behind anyway
      const cap = 16 << 20;
      if (_buffer.length > cap) {
        final b = _buffer.takeBytes();
        _buffer.add(b.sublist(cap ~/ 2)); // keep the tail
      }
    }, onDone: () => _done = true, onError: (_) => _done = true);
    _proc!.stderr.drain<void>();
    _proc!.exitCode.then((_) => _done = true);
    _currentUrl = 'http://127.0.0.1:$_port/a$_gen.wav';
    return _currentUrl!;
  }

  Future<void> stop() async {
    _gen++;
    _proc?.kill();
    _proc = null;
    _done = true;
    _buffer.takeBytes();
  }

  void dispose() {
    stop();
    _server?.close();
  }
}
