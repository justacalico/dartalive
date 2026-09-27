import 'dart:io';
import '../lib/io/kdenlive_import.dart';
import '../lib/io/media_resolver.dart';
import '../lib/engine/graph.dart';

Future<void> main(List<String> args) async {
  final kd = args[0];
  final dir = args[1];
  final p = await KdenliveImport.run(kd);
  final resolver = MediaResolver(dir);
  await resolver.resolveAll(p);
  final seq = p.mainSequence ?? p.sequences.first;
  final gb = GraphBuilder(project: p, resolver: resolver);
  final g = gb.build(seq, 0, 300, audio: true);
  File('/tmp/egraph.txt').writeAsStringSync(g.filterComplex);
  final proc = await Process.start('ffmpeg', [
    '-hide_banner', '-loglevel', 'warning', '-y',
    ...g.inputArgs,
    '-filter_complex', g.filterComplex,
    '-map', '[${g.videoLabel}]',
    '-map', '[${g.audioLabel}]',
    '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '23', '-pix_fmt', 'yuv420p',
    '-c:a', 'aac', '-b:a', '192k',
    '/tmp/export_test.mp4',
  ]);
  proc.stderr.transform(const SystemEncoding().decoder).listen(print);
  final code = await proc.exitCode;
  print('export exit: $code size=${File('/tmp/export_test.mp4').lengthSync()}');
}
