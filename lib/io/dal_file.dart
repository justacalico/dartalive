import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import '../models/model.dart';

/// .dal files are ZIP archives:
///   project.json   - the whole document
///   cache/thumbs/  - optional bundled thumbnails (future)
///   titles/        - title xml/json payloads if we ever externalize them
class DalFile {
  static Future<Project> read(String path) async {
    final bytes = await File(path).readAsBytes();
    final arch = ZipDecoder().decodeBytes(bytes);
    final f = arch.findFile('project.json');
    if (f == null) throw const FormatException('project.json missing');
    final json =
        jsonDecode(utf8.decode(f.content as List<int>)) as Map<String, dynamic>;
    return Project.fromJson(json);
  }

  static Future<void> write(String path, Project project) async {
    final arch = Archive();
    final data = utf8.encode(const JsonEncoder.withIndent('  ')
        .convert(project.toJson()));
    arch.addFile(ArchiveFile('project.json', data.length, data));
    final zip = ZipEncoder().encode(arch);
    if (zip == null) throw StateError('zip encode failed');
    // atomic-ish write: temp file then rename
    final tmp = File('$path.tmp');
    await tmp.writeAsBytes(zip, flush: true);
    await tmp.rename(path);
  }

  /// Cheap sniff: is this file a .dal (zip with project.json)?
  static bool isDal(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      final arch = ZipDecoder().decodeBytes(bytes);
      return arch.findFile('project.json') != null;
    } catch (_) {
      return false;
    }
  }
}
