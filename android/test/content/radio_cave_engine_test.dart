import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/radio_cave_engine.dart';

RadioCaveEngine fresh() => RadioCaveEngine()..begin(null);

void run(RadioCaveEngine e, String cmds) {
  for (final c in cmds.split(',')) {
    e.dispatch(c.trim());
  }
}

// Walkthrough up to a repaired station at the Operating Room, power off.
const _repair = 'n,n,w,s,t fuel,n,u fuel,t key,e,e,u key,e,'
    'xyzzy,d key,jn78dh,t tube,w,t choke,w,w,s,s,f choke,n,n,e,e,'
    'u choke,u tube';

void main() {
  test('a new game starts in the forest with the long description', () {
    final e = fresh();
    expect(e.room, 1);
    expect(e.body, startsWith('A narrow forest trail.'));
    expect(e.exitLetters, ['N']);
  });

  test('movement, blocked exits and the locked Captain door', () {
    final e = fresh();
    run(e, 'n,n');
    expect(e.room, 3);
    e.dispatch('w');
    run(e, 'e');   // back to corridor
    run(e, 'e');   // operating room
    expect(e.room, 7);
    e.dispatch('e');
    expect(e.room, 7);
    expect(e.message, "You can't go that way.");
  });

  test('revisit shows the short description, LOOK the full one', () {
    final e = fresh();
    run(e, 'n,s');
    expect(e.body, startsWith('Forest trail.'));
    e.dispatch('l');
    expect(e.body, startsWith('A narrow forest trail.'));
  });

  test('inventory holds two items and prefix matching works', () {
    final e = fresh();
    run(e, 'n,n,w,s');
    expect(e.body, contains('You see: fuel canister, operating manual and microphone.'));
    e.dispatch('t m');
    expect(e.message, 'Which one?');
    run(e, 't ma,t f');
    expect(e.invCount, 2);
    e.dispatch('t mi');
    expect(e.message, 'Your hands are full. Drop something.');
    e.dispatch('d f');
    expect(e.message, 'You drop the fuel canister.');
    e.dispatch('i');
    expect(e.message, 'Carrying: operating manual.');
  });

  test('the key appears only once the generator runs', () {
    final e = fresh();
    run(e, 'n,n,w');
    expect(e.body, isNot(contains('brass key')));
    run(e, 's,t fuel,n,u fuel');
    expect(e.generator, isTrue);
    e.dispatch('l');
    expect(e.body, contains('brass key'));
  });

  test('wall scribbles: first XYZZY, then the QSO opener, QRS halves speed', () {
    final e = fresh();
    run(e, 'n,n,e,l wall');
    expect(e.clue!.text, 'xyzzy');
    expect(e.clue!.wpm, 16);
    e.dispatch('r wall');
    expect(e.clue!.text, 'de rc0 qsl <SK>');
    e.dispatch('qrs');
    expect(e.clue!.wpm, 8);
    expect(e.clue!.text, 'de rc0 qsl <SK>');
  });

  test('QRS without a clue replays nothing', () {
    final e = fresh();
    e.dispatch('qrs');
    expect(e.clue, isNull);
    expect(e.message, 'QRS — nothing to replay yet');
  });

  test('XYZZY keyed bare opens the Captain office in the operating room', () {
    final e = fresh();
    run(e, 'n,n,e,xyzzy,e');
    expect(e.room, 11);
  });

  test('touching the live choke is fatal', () {
    final e = fresh();
    run(e, 'n,n,e,u s,t choke');
    expect(e.phase, RcPhase.dead);
  });

  test('installing the tube with power on is fatal', () {
    final e = fresh();
    run(e, 'n,n,e,xyzzy,e,jn78dh,t tube,w,u s');
    expect(e.phase, RcPhase.playing);
    e.dispatch('u tube');
    expect(e.phase, RcPhase.dead);
  });

  test('power can be switched on again once the station is repaired', () {
    final e = fresh();
    run(e, '$_repair,u s');
    expect(e.masterPower, isTrue);
    expect(e.phase, RcPhase.playing);
  });

  test('walkthrough: repair the station and win the QSO', () {
    final e = fresh();
    run(e, _repair);
    expect(e.tubeInstalled, isTrue);
    expect(e.chokeInstalled, isTrue);
    run(e, 'w,n,u s');
    expect(e.antennaGrounded, isFalse);
    run(e, 's,e,u s,u tx');
    expect(e.txMode, isTrue);
    e.dispatch('de rc0 qsl K');
    expect(e.qsoStage, 2);
    expect(e.clue!.text, 'rc0 de ir7 pse qsz');
    e.dispatch('de rc0 qsl K');
    expect(e.body, contains('patiently repeats'));
    e.dispatch('de de rc0 rc0 qsl qsl K K');
    expect(e.phase, RcPhase.won);
    expect(e.wonText, contains('Steps taken: ${e.steps}'));
  });

  test('QSO phrases explain why the station cannot transmit', () {
    final e = fresh();
    e.dispatch('de rc0 qsl K');
    expect(e.message, "You're not at the transmitter.");
    run(e, 'n,n,e');
    e.dispatch('de rc0 qsl k');
    expect(e.message, 'Master power is off.');
  });

  test('keying TX into a grounded antenna destroys the tube', () {
    final e = fresh();
    run(e, '$_repair,u s,u tx');
    expect(e.tubeInstalled, isFalse);
    expect(e.message, 'Station dead. Key NEW to restart.');
    expect(e.body, contains('station cannot be revived'));
  });

  test('NEW asks for Y and then restarts', () {
    final e = fresh();
    run(e, 'n,n,new');
    expect(e.pendingNewConfirm, isTrue);
    e.dispatch('y');
    expect(e.room, 1);
    expect(e.steps, 0);
    expect(e.message, 'Game restarted.');
  });

  test('save and resume keep the progress', () {
    final e = fresh();
    run(e, 'n,n,w,s,t fuel');
    final saved = e.toSave();
    final f = RadioCaveEngine();
    expect(f.begin(saved), isTrue);
    expect(f.room, 5);
    expect(f.invCount, 1);
    expect(f.message, 'Welcome back.');
    expect(RadioCaveEngine().begin('garbage'), isFalse);
  });

  test('command buffer characters follow the firmware convention', () {
    expect(rcBufferChar('A'), 'a');
    expect(rcBufferChar('SK'), 'K');
    expect(rcBufferChar('AS'), 'S');
    expect(rcBufferChar('*'), isNull);
    expect(rcIsInstantCommand('s', pendingNewConfirm: false), isTrue);
    expect(rcIsInstantCommand('S', pendingNewConfirm: false), isFalse);
    expect(rcIsInstantCommand('n', pendingNewConfirm: false), isFalse);
    expect(rcIsInstantCommand('y', pendingNewConfirm: false), isFalse);
    expect(rcIsInstantCommand('y', pendingNewConfirm: true), isTrue);
  });
}
