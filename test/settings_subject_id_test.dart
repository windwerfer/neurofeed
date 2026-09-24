import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _uuidRe = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load generates subjectId UUID v4 when missing', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    expect(settings.subjectId, isNotEmpty);
    expect(settings.subjectId, matches(_uuidRe));
    expect(settings.subjectNickname, isNull);
    expect(settings.subjectInfo.id, settings.subjectId);
    expect(settings.subjectInfo.toJson(), {'id': settings.subjectId});
  });

  test('load keeps existing subjectId and does not invent nickname', () async {
    SharedPreferences.setMockInitialValues({
      'subjectId': '11111111-2222-4333-8444-555555555555',
    });
    final settings = await Settings.load();
    expect(settings.subjectId, '11111111-2222-4333-8444-555555555555');
    expect(settings.subjectNickname, isNull);
  });

  test('empty subjectId is regenerated on load', () async {
    SharedPreferences.setMockInitialValues({'subjectId': ''});
    final settings = await Settings.load();
    expect(settings.subjectId, isNotEmpty);
    expect(settings.subjectId, matches(_uuidRe));
  });

  test('nickname persists and appears in SubjectInfo.toJson', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    await settings.setSubjectNickname('  wind  ');
    expect(settings.subjectNickname, 'wind');
    expect(settings.subjectInfo.toJson(), {
      'id': settings.subjectId,
      'nickname': 'wind',
    });
    await settings.setSubjectNickname('   ');
    expect(settings.subjectNickname, isNull);
    expect(settings.subjectInfo.toJson().containsKey('nickname'), isFalse);
  });

  test('second load reuses the same generated subjectId', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await Settings.load();
    final id = first.subjectId;
    final second = await Settings.load();
    expect(second.subjectId, id);
  });
}
