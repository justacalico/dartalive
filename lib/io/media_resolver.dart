import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import '../models/model.dart';

/// Resolves media paths relative to the project file, and relocates media
/// when the drive/parent folder moved (removable-media workflow).
///
/// Identity hash = md5 over file size + first and last 64KiB. Fast on huge
/// files and stable across mounts.
class MediaResolver {
  final String projectDir;
  MediaResolver(this.projectDir);

  static String normalize(String p) =>
      p.replaceAll('\\', '/').replaceAll(RegExp('/+'), '/');

  /// Path relative to [projectDir] when possible, else absolute.
  String toRelative(String absPath) {
    final norm = normalize(absPath);
    final base = normalize(projectDir);
    if (norm.startsWith('$base/')) {
      return norm.substring(base.length + 1);
    }
    // try ../ style relativisation
    final absParts = norm.split('/');
    final baseParts = base.split('/');
    var i = 0;
    while (i < absParts.length &&
        i < baseParts.length &&
        absParts[i] == baseParts[i]) {
      i++;
    }
    if (i == 0) return norm; // different root (windows drive), keep absolute
    final ups = List.filled(baseParts.length - i, '..').join('/');
    final rel = [if (ups.isNotEmpty) ups, ...absParts.sublist(i)].join('/');
    // if we had to climb more than 3 levels keep absolute (likely unrelated)
    if (baseParts.length - i > 3) return norm;
    return rel;
  }

  String toAbsolute(String relOrAbs) {
    if (relOrAbs.startsWith('/') || RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(relOrAbs)) {
      return relOrAbs;
    }
    return '$projectDir/$relOrAbs';
  }

  /// Resolve an asset to a real file. Order:
  /// 1. stored relative/absolute path
  /// 2. search project dir recursively for the filename
  /// 3. search for hash match (same file, renamed)
  /// Returns null when the media is offline. Fills project.resolvedPaths.
  Future<String?> resolve(MediaAsset a, {bool search = true}) async {
    if (a.relPath != null) {
      final abs = toAbsolute(a.relPath!);
      if (await File(abs).exists()) return abs;
    }
    if (!search || a.fileName == null) return null;

    // one directory scan per resolveAll; filename first, hash when known
    final listing = await _listFiles();
    final nameMatch = listing
        .where((f) => f.uri.pathSegments.last == a.fileName)
        .toList();
    for (final f in nameMatch) {
      final st = await f.stat();
      if (a.fileSize != 0 && st.size != a.fileSize) continue;
      if (a.hash != null && a.fileSize > 0) {
        if (await hashFile(f.path) == a.hash) return f.path;
      } else {
        return f.path;
      }
    }
    // hash search over the whole tree (renamed/moved file)
    if (a.hash != null && a.fileSize > 0) {
      for (final f in listing) {
        final st = await f.stat();
        if (st.size != a.fileSize) continue;
        if (await hashFile(f.path) == a.hash) return f.path;
      }
    }
    return null;
  }

  List<File>? _listing;
  Future<List<File>> _listFiles() async {
    if (_listing != null) return _listing!;
    final out = <File>[];
    try {
      await for (final e in Directory(projectDir)
          .list(recursive: true, followLinks: false)) {
        if (e is File) out.add(e);
      }
    } catch (_) {}
    return _listing = out;
  }

  /// Drop the cached directory listing (e.g. after relink or media copy).
  void invalidateListing() => _listing = null;

  static Future<String> hashFile(String path) async {
    final f = File(path);
    final size = await f.length();
    const chunk = 64 * 1024;
    final raf = await f.open();
    try {
      final head = await raf.read(chunk);
      List<int> tail = const [];
      if (size > chunk) {
        await raf.setPosition(size - chunk);
        tail = await raf.read(chunk);
      }
      final buf = BytesBuilder()
        ..add(utf8.encode('$size'))
        ..add(head)
        ..add(tail);
      return md5.convert(buf.takeBytes()).toString();
    } finally {
      await raf.close();
    }
  }

  /// Resolve every file asset; returns ids that stayed offline.
  Future<List<String>> resolveAll(Project p) async {
    final missing = <String>[];
    for (final a in p.assets) {
      if (a.relPath == null) continue;
      final r = await resolve(a);
      if (r == null) {
        missing.add(a.id);
      } else {
        p.resolvedPaths[a.id] = r;
        // re-relativize if we moved (media got relocated)
        final rel = toRelative(r);
        if (rel != a.relPath) a.relPath = rel;
      }
    }
    return missing;
  }
}
