import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/strings.dart';

String _in(Lang lang, String Function() said) {
  useLang(lang);
  return said();
}

void main() {
  tearDown(() => useLang(Lang.uk));

  test('the search bar\'s placeholder is no longer in Ukrainian than in '
      'English, which fits beside its three buttons', () {
    final uk = _in(Lang.uk, () => txt.findStop);
    final en = _in(Lang.en, () => txt.findStop);

    expect(uk.length, lessThanOrEqualTo(en.length), reason: uk);
  });
}
