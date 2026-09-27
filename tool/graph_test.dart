// CLI harness: import dance.kdenlive, build the graph, render one frame.
import 'dart:io';
import '../lib/io/kdenlive_import.dart';
import '../lib/io/media_resolver.dart';
import '../lib/engine/graph.dart';

Future<void> main(List<String> args) async {
  final kd = args.isNotEmpty
      ? args[0]
      : '/home/calico/dartalive/.devinorium-attachments/1e101804-a191-46c8-a343-864bece5c586/0_dance.kdenlive';
  final p = await KdenliveImport.run(kd);
  print('assets: ${p.assets.length}  sequences: ${p.sequences.length}');
  for (final s in p.sequences) {
    print('  seq ${s.name}: tracks=${s.tracks.length} dur=${s.duration}f');
    for (final t in s.tracks) {
      print('    ${t.kind.name} ${t.name}: ${t.clips.length} clips');
    }
  }
  // resolve media: use dir given as arg2 or kdenlive dir
  final dir = args.length > 1 ? args[1] : File(kd).parent.path;
  final resolver = MediaResolver(dir);
  final missing = await resolver.resolveAll(p);
  print('offline assets: ${missing.length}');
  for (final id in missing) {
    final a = p.assetById(id);
    print('  MISSING ${a?.name} rel=${a?.relPath}');
  }
  final seq = p.mainSequence ?? p.sequences.first;
  final frame = args.length > 2 ? int.parse(args[2]) : 100;
  final endF = args.length > 3 ? int.parse(args[3]) : frame + 60;
  final gb = GraphBuilder(project: p, resolver: resolver, width: 1280, height: 720);
  final g = gb.build(seq, frame, endF, audio: false);
  File('/tmp/graph.txt').writeAsStringSync(g.filterComplex);
  print('inputs: ${g.inputArgs.length ~/ 4} filter bytes: ${g.filterComplex.length}');
  final ffargs = [
    '-hide_banner', '-loglevel', 'error',
    ...g.inputArgs,
    '-filter_complex', g.filterComplex,
    '-map', '[${g.videoLabel}]',
    '-frames:v', '10',
    '-f', 'image2pipe', '-vcodec', 'mjpeg', '-q:v', '4',
    '-',
  ];
  final proc = await Process.start('ffmpeg', ffargs);
  final out = File('/tmp/frame.jpg').openWrite();
  await for (final c in proc.stdout) {
    out.add(c);
  }
  final err = await proc.stderr.transform(const SystemEncoding().decoder).join();
  await out.close();
  final code = await proc.exitCode;
  print('ffmpeg exit: $code  bytes: ${File('/tmp/frame.jpg').lengthSync()}');
  if (err.isNotEmpty) print('stderr:\n${err.split('\n').take(25).join('\n')}');
}
