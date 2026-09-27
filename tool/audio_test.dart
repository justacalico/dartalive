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
  final g = gb.build(seq, 0, 600, audio: true, video: false);
  File('/tmp/agraph.txt').writeAsStringSync(g.filterComplex);
  final ffargs = [
    '-hide_banner', '-loglevel', 'warning',
    ...g.inputArgs,
    '-filter_complex', g.filterComplex,
    '-map', '[${g.audioLabel}]',
    '-t', '5', '-f', 'wav', '/tmp/audio_test.wav',
  ];
  File('/tmp/audio_cmd.txt').writeAsStringSync(
      ffargs.map((e) => "'${e.replaceAll("'", "'\\''")}'").join(' '));
  print('wrote /tmp/audio_cmd.txt');
}
