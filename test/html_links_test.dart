import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_sources/html.dart';

void main() {
  List<String> urls(String text) =>
      getLinksInLines(text).map((link) => link.key).toList();

  test('keeps parentheses that are part of the URL', () {
    const apk =
        'https://static.gl-inet.com/edge-app-staging/gl-inet-app-google/2.9.0/1793610269715/glinet-app_2.9.0(275)_en.apk';
    expect(urls('{"url": "$apk"}'), [apk]);
    expect(urls(apk), [apk]);
    expect(getLinksInLines(apk).single.value, 'glinet-app_2.9.0(275)_en.apk');
    expect(urls('https://en.wikipedia.org/wiki/Foo_(bar)'), [
      'https://en.wikipedia.org/wiki/Foo_(bar)',
    ]);
  });

  test('drops parentheses and punctuation from the surrounding text', () {
    expect(urls('(see https://example.com/app.apk)'), [
      'https://example.com/app.apk',
    ]);
    expect(urls('Download (https://example.com/app.apk).'), [
      'https://example.com/app.apk',
    ]);
    expect(urls('Get https://example.com/app_(1).apk, then install'), [
      'https://example.com/app_(1).apk',
    ]);
    expect(
      urls('Links: https://example.com/a.apk; https://example.com/b.apk!'),
      ['https://example.com/a.apk', 'https://example.com/b.apk'],
    );
  });

  test('still splits URLs at quotes, brackets and whitespace', () {
    expect(
      urls(
        '<a href="https://example.com/a.apk">x</a> [https://example.com/b.apk] {https://example.com/c.apk}',
      ),
      [
        'https://example.com/a.apk',
        'https://example.com/b.apk',
        'https://example.com/c.apk',
      ],
    );
  });
}
