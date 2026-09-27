// Build the example .dal: import dance.kdenlive, resolve media under the
// example dir, save as dance.dal there.
import 'dart:io';
import '../lib/io/kdenlive_import.dart';
import '../lib/io/dal_file.dart';
import '../lib/io/media_resolver.dart';

Future<void> main(List<String> args) async {
  final kd = args[0];
  final outDir = args[1];
  final p = await KdenliveImport.run(kd);
  final resolver = MediaResolver(outDir);
  // re-relativize paths against the example dir
  for (final a in p.assets) {
    if (a.relPath == null) continue;
    final abs = resolver.toAbsolute(a.relPath!);
    if (File(abs).existsSync()) {
      a.relPath = resolver.toRelative(abs);
      p.resolvedPaths[a.id] = abs;
    }
  }
  final missing = await resolver.resolveAll(p);
  for (final id in missing) {
    final a = p.assetById(id);
    print('offline: ${a?.name}');
  }
  p.name = 'Dance Interview';
  final out = '$outDir/dance.dal';
  await DalFile.write(out, p);
  print('wrote $out (${File(out).lengthSync()} bytes)');
}
