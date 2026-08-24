import 'dart:io';
 
 import 'package:flutter_test/flutter_test.dart';
 import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
 import 'package:muse_ml/src/feedback/protocol.dart';
 import 'package:muse_ml/src/feedback/session_storage.dart';
 import 'package:muse_ml/src/feedback/session_store.dart';
 import 'package:muse_ml/src/rust/api/session_format.dart';
 import 'package:muse_ml/src/rust/frb_generated.dart';
 
 void main() {
   TestWidgetsFlutterBinding.ensureInitialized();
   setUpAll(() async {
     await RustLib.init(
       externalLibrary: ExternalLibrary.open(
         '${Directory.current.path}/rust/target/debug/librust_lib_muse_ml.so',
       ),
     );
   });
 
   test('SessionStore publish and list test', () async {
     final tmp = await Directory.systemTemp.createTemp('muse_store_test');
     final storage = FileSystemSessionStorage(tmp);
     final store = SessionStore(storage: Future.value(storage));
 
     final metadata = SessionMetadata(
       protocol: ProtocolType.drowsiness,
       durationMinutes: 5,
       elapsedSeconds: 300,
       sound: 'Ambient Drone',
       savedAt: DateTime.now().toIso8601String(),
     );
 
     // Use v5 format with empty computed frames (dummy body [1,2,3,4] is valid v4 raw body)
     await store.publishSession('test1234', [1, 2, 3, 4], metadata, computedFrames: const <ComputedFrame>[]);
     final list = await store.list();
     expect(list.length, 1);
     expect(list.first.id, 'test1234');
     expect(list.first.metadata.protocol, ProtocolType.drowsiness);
 
     await tmp.delete(recursive: true);
   });
 }
