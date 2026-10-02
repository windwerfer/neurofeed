import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/app_folder.dart';
import 'package:neurofeed/src/feedback/folder_move.dart';
import 'package:neurofeed/src/feedback/session_sqlite.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  test('xdg failure, empty, and home use Documents/neurofeed', () {
    const home = '/home/person';
    expect(
      desktopAppFolderPath(home: home, xdg: null),
      p.join(home, 'Documents', 'neurofeed'),
    );
    expect(
      desktopAppFolderPath(home: home, xdg: ''),
      p.join(home, 'Documents', 'neurofeed'),
    );
    expect(
      desktopAppFolderPath(home: home, xdg: home),
      p.join(home, 'Documents', 'neurofeed'),
    );
    expect(
      desktopAppFolderPath(home: home, xdg: '$home/'),
      p.join(home, 'Documents', 'neurofeed'),
    );
    expect(
      desktopAppFolderPath(home: home, xdg: 'relative/docs'),
      p.join(home, 'Documents', 'neurofeed'),
    );
  });

  test('a real xdg documents directory gets a neurofeed child', () {
    const home = '/home/person';
    expect(
      desktopAppFolderPath(home: home, xdg: '/home/person/Documents'),
      p.join(home, 'Documents', 'neurofeed'),
    );
    expect(
      desktopAppFolderPath(home: home, xdg: '/data/docs'),
      p.join('/data/docs', 'neurofeed'),
    );
  });

  test('xdg failure creates Documents and neurofeed', () async {
    final home = await Directory.systemTemp.createTemp('nf_home_');
    addTearDown(() => home.delete(recursive: true));
    final dir = await desktopNeurofeedDir(
      env: {'HOME': home.path},
      readXdg: () async => throw ProcessException(
        'xdg-user-dir',
        ['DOCUMENTS'],
        'Permission denied',
        13,
      ),
    );
    expect(dir.path, p.join(home.path, 'Documents', 'neurofeed'));
    expect(dir.existsSync(), isTrue);
    expect(Directory(p.join(home.path, 'Documents')).existsSync(), isTrue);
    expect(dir.path.contains('meditation feedback'), isFalse);
  });

  test('mobile cache and models stay in the system app folder', () async {
    final support = await Directory.systemTemp.createTemp('nf_support_');
    addTearDown(() => support.delete(recursive: true));
    Future<Directory> readSupport() async => support;

    final cache = await cacheDirectory(
      filesystemAppFolder: 'content://com.example/tree/primary%3ANeuro',
      layout: AppDataLayout.mobile,
      readSystemAppFolder: readSupport,
    );
    final models = await modelsRoot(
      sessionFolder: '/storage/picked',
      layout: AppDataLayout.mobile,
      readSystemAppFolder: readSupport,
    );
    final safModels = await modelsRoot(
      sessionFolder: 'content://com.example/tree/primary%3ANeuro',
      layout: AppDataLayout.mobile,
      readSystemAppFolder: readSupport,
    );
    expect(cache.path, p.join(support.path, '.cache'));
    expect(models.path, p.join(support.path, 'ai_models'));
    expect(safModels.path, models.path);
    expect(cache.path.contains('cache'), isTrue);
    expect(cache.path.contains(support.path), isTrue);
  });

  test('desktop cache follows the app folder and matches scratch', () async {
    final root = await Directory.systemTemp.createTemp('nf_app_');
    addTearDown(() => root.delete(recursive: true));
    final storage = FileSystemSessionStorage(root);
    final cache = await cacheDirectory(
      filesystemAppFolder: root.path,
      layout: AppDataLayout.desktop,
    );
    final scratch = await scratchDirectory(
      storage,
      layout: AppDataLayout.desktop,
    );
    final sqlite = await resolveSessionCacheDir(
      storage,
      layout: AppDataLayout.desktop,
    );
    expect(cache.path, p.join(root.path, '.cache'));
    expect(scratch.path, cache.path);
    expect(sqlite.path, cache.path);
  });

  test('SAF tree label uses the decoded document path', () {
    expect(
      safTreeLabel(
        'content://com.android.externalstorage.documents/tree/primary%3ADownload%2Fneurofeed',
      ),
      'Download/neurofeed',
    );
  });

  test('empty trees and cache tmp files do not count', () async {
    final root = await Directory.systemTemp.createTemp('nf_count_');
    addTearDown(() => root.delete(recursive: true));
    await Directory(p.join(root.path, 'export')).create();
    await Directory(p.join(root.path, '.cache')).create();
    await Directory(p.join(root.path, 'ai_models')).create();
    await File(
      p.join(root.path, '.cache', 'tmp_1.neurofeed'),
    ).writeAsBytes([1]);
    final plan = await planFilesystemMove(
      root: root,
      includeCacheAndModels: true,
    );
    expect(plan.prompts, isFalse);
    expect(plan.export, isFalse);
    expect(plan.cache, isFalse);
    expect(plan.models, isFalse);
    expect(plan.files, hasLength(1));
    expect(plan.files.single.deleteOnly, isTrue);
  });

  test(
    'desktop plan includes cache and models; mobile plan does not',
    () async {
      final root = await Directory.systemTemp.createTemp('nf_plan_');
      addTearDown(() => root.delete(recursive: true));
      await File(p.join(root.path, 'session_a.neurofeed')).writeAsBytes([1]);
      await File(p.join(root.path, 'recording_b.neurofeed')).writeAsBytes([2]);
      await File(p.join(root.path, 'notes.txt')).writeAsBytes([3]);
      await Directory(
        p.join(root.path, 'export', 'batch'),
      ).create(recursive: true);
      await File(
        p.join(root.path, 'export', 'batch', 'a.csv'),
      ).writeAsBytes([4]);
      await Directory(p.join(root.path, '.cache')).create();
      await File(
        p.join(root.path, '.cache', 'session_metadata.db'),
      ).writeAsBytes([5]);
      await File(
        p.join(root.path, '.cache', 'tmp_live.neurofeed'),
      ).writeAsBytes([6]);
      await Directory(
        p.join(root.path, 'ai_models', 'cbramod_a_vig'),
      ).create(recursive: true);
      await File(
        p.join(root.path, 'ai_models', 'cbramod_a_vig', 'pack_manifest.json'),
      ).writeAsBytes([7]);

      final desktop = await planFilesystemMove(
        root: root,
        includeCacheAndModels: true,
      );
      expect(desktop.sessions, 1);
      expect(desktop.recordings, 1);
      expect(desktop.export, isTrue);
      expect(desktop.cache, isTrue);
      expect(desktop.models, isTrue);
      expect(desktop.prompts, isTrue);
      expect(desktop.files.any((f) => f.relative == 'notes.txt'), isFalse);
      expect(
        desktop.files.any(
          (f) => f.relative == '.cache/tmp_live.neurofeed' && f.deleteOnly,
        ),
        isTrue,
      );

      final mobile = await planFilesystemMove(
        root: root,
        includeCacheAndModels: false,
      );
      expect(mobile.sessions, 1);
      expect(mobile.export, isTrue);
      expect(mobile.cache, isFalse);
      expect(mobile.models, isFalse);
      expect(mobile.files.any((f) => f.relative.startsWith('.cache')), isFalse);
      expect(
        mobile.files.any((f) => f.relative.startsWith('ai_models')),
        isFalse,
      );
    },
  );

  test('a full move copies trees, deletes sources, and drops tmp', () async {
    final srcDir = await Directory.systemTemp.createTemp('nf_mv_src_');
    final dstDir = await Directory.systemTemp.createTemp('nf_mv_dst_');
    addTearDown(() => srcDir.delete(recursive: true));
    addTearDown(() => dstDir.delete(recursive: true));
    await File(
      p.join(srcDir.path, 'session_a.neurofeed'),
    ).writeAsBytes(List<int>.generate(1000, (i) => i % 256));
    await File(p.join(srcDir.path, 'recording_b.neurofeed')).writeAsBytes([2]);
    await Directory(p.join(srcDir.path, 'export')).create();
    await File(p.join(srcDir.path, 'export', 'a.csv')).writeAsBytes([3, 3]);
    await Directory(p.join(srcDir.path, '.cache')).create();
    await File(
      p.join(srcDir.path, '.cache', 'session_metadata.db'),
    ).writeAsBytes([4, 4, 4]);
    await File(
      p.join(srcDir.path, '.cache', 'tmp_x.neurofeed'),
    ).writeAsBytes([9]);
    await Directory(
      p.join(srcDir.path, 'ai_models', 'reve'),
    ).create(recursive: true);
    await File(
      p.join(srcDir.path, 'ai_models', 'reve', 'config.json'),
    ).writeAsBytes([8]);

    final src = FileSystemSessionStorage(srcDir);
    final dst = FileSystemSessionStorage(dstDir);
    final plan = await planFilesystemMove(
      root: srcDir,
      includeCacheAndModels: true,
    );
    final moved = await commitFolderMove(
      source: src,
      target: dst,
      files: plan.files,
    );
    expect(moved, 2);
    expect(File(p.join(dstDir.path, 'session_a.neurofeed')).lengthSync(), 1000);
    expect(
      File(p.join(srcDir.path, 'session_a.neurofeed')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(srcDir.path, 'recording_b.neurofeed')).existsSync(),
      isFalse,
    );
    expect(File(p.join(dstDir.path, 'export', 'a.csv')).existsSync(), isTrue);
    expect(
      File(p.join(dstDir.path, '.cache', 'session_metadata.db')).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(dstDir.path, 'ai_models', 'reve', 'config.json'),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(dstDir.path, '.cache', 'tmp_x.neurofeed')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(srcDir.path, '.cache', 'tmp_x.neurofeed')).existsSync(),
      isFalse,
    );
    expect(File(p.join(srcDir.path, 'export', 'a.csv')).existsSync(), isFalse);
  });

  test(
    'a failed copy removes partial destination files and keeps sources',
    () async {
      final srcDir = await Directory.systemTemp.createTemp('nf_fail_src_');
      final dstDir = await Directory.systemTemp.createTemp('nf_fail_dst_');
      addTearDown(() => srcDir.delete(recursive: true));
      addTearDown(() => dstDir.delete(recursive: true));
      await File(
        p.join(srcDir.path, 'session_a.neurofeed'),
      ).writeAsBytes([1, 2]);
      await File(
        p.join(srcDir.path, 'recording_b.neurofeed'),
      ).writeAsBytes([3]);
      final src = FileSystemSessionStorage(srcDir);
      final dst = FileSystemSessionStorage(dstDir);
      final plan = await planFilesystemMove(
        root: srcDir,
        includeCacheAndModels: true,
      );
      var copies = 0;
      await expectLater(
        commitFolderMove(
          source: src,
          target: dst,
          files: plan.files,
          copyForTest: (file) async {
            copies++;
            if (copies > 1) throw StateError('disk full');
            final dest = File(
              p.joinAll([dstDir.path, ...file.relative.split('/')]),
            );
            await dest.parent.create(recursive: true);
            await File(
              p.joinAll([srcDir.path, ...file.relative.split('/')]),
            ).copy(dest.path);
          },
        ),
        throwsA(isA<FolderMoveException>()),
      );
      expect(
        File(p.join(srcDir.path, 'session_a.neurofeed')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(srcDir.path, 'recording_b.neurofeed')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(dstDir.path, 'session_a.neurofeed')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(dstDir.path, 'recording_b.neurofeed')).existsSync(),
        isFalse,
      );
    },
  );

  test('an existing destination name fails before overwrite', () async {
    final srcDir = await Directory.systemTemp.createTemp('nf_col_src_');
    final dstDir = await Directory.systemTemp.createTemp('nf_col_dst_');
    addTearDown(() => srcDir.delete(recursive: true));
    addTearDown(() => dstDir.delete(recursive: true));
    await File(p.join(srcDir.path, 'session_a.neurofeed')).writeAsBytes([1]);
    await File(p.join(srcDir.path, 'recording_b.neurofeed')).writeAsBytes([2]);
    await File(p.join(dstDir.path, 'session_a.neurofeed')).writeAsBytes([9, 9]);
    final plan = await planFilesystemMove(
      root: srcDir,
      includeCacheAndModels: true,
    );
    await expectLater(
      commitFolderMove(
        source: FileSystemSessionStorage(srcDir),
        target: FileSystemSessionStorage(dstDir),
        files: plan.files,
      ),
      throwsA(isA<FolderMoveException>()),
    );
    expect(File(p.join(dstDir.path, 'session_a.neurofeed')).readAsBytesSync(), [
      9,
      9,
    ]);
    expect(
      File(p.join(srcDir.path, 'session_a.neurofeed')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(srcDir.path, 'recording_b.neurofeed')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(dstDir.path, 'recording_b.neurofeed')).existsSync(),
      isFalse,
    );
  });
}
