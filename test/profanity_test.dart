import 'package:arena/data/profanity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flags plurals, other forms and disguised spellings', () {
    for (final t in [
      'For fucks sake, who does that',
      'fucked up',
      'what the f*ck',
      'shitty take',
      'bitches',
      'dicks',
      'kill yourself',
    ]) {
      expect(hasProfanity(t), isTrue, reason: t);
    }
  });

  test('leaves innocent words alone', () {
    for (final t in [
      'cocktail party',
      'Charles Dickens',
      'prickly pear',
      'grapes and rapeseed',
      'class assignment',
      'Scunthorpe',
    ]) {
      expect(hasProfanity(t), isFalse, reason: t);
    }
  });
}
