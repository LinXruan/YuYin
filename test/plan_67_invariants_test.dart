import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';
import 'package:yuyin/services/selection/selection_invariants.dart';

SingleWorkResult _note(String work, int count) {
  return SingleWorkResult(
    items: [
      for (var i = 1; i <= count; i++)
        MediaItem(url: '$work#r$i', type: MediaType.image),
    ],
    cookie: '',
    isImagePost: true,
  );
}

SingleWorkResult _video(String work) {
  return SingleWorkResult(
    items: [
      MediaItem(url: '$work#high', type: MediaType.video, bitRate: 3000000),
      MediaItem(url: '$work#mid', type: MediaType.video, bitRate: 1500000),
      MediaItem(url: '$work#low', type: MediaType.video, bitRate: 700000),
    ],
    cookie: '',
    isImagePost: false,
  );
}

SaveSelectionSession _session() {
  final works = <String, List<SaveWorkItem>>{};
  for (var a = 1; a <= 2; a++) {
    works['a$a'] = [
      for (var w = 1; w <= 5; w++)
        SaveWorkItem(
          url: 'a$a-w$w',
          kind: w.isEven ? WorkMediaKind.video : WorkMediaKind.image,
        ),
    ];
  }
  final session = SaveSelectionSession.home(
    profiles: const [
      UserHomeProfile(secUid: 'a1', nickname: '作者一'),
      UserHomeProfile(secUid: 'a2', nickname: '作者二'),
    ],
    worksBySecUid: works,
    seed: const TerminalSeed(),
  );
  for (final work in session.allWorks) {
    session.ingest(
      work.url,
      work.isVideo ? _video(work.url) : _note(work.url, 4),
    );
  }
  return session;
}

void main() {
  test('PLAN_67 随机命令后缓存与全量重算一致', () {
    final session = _session();
    final random = Random(67);

    for (var i = 0; i < 2000; i++) {
      final authors = session.authors;
      final works = session.allWorks;
      final work = works[random.nextInt(works.length)];
      final op = random.nextInt(15);
      switch (op) {
        case 0:
        case 1:
          session.toggleAuthor(authors[random.nextInt(authors.length)].secUid);
          break;
        case 2:
          session.toggleWork(work.url);
          break;
        case 3:
          session.setWork(
            work.url,
            random.nextBool() ? SelectionState.all : SelectionState.none,
          );
          break;
        case 4:
          if (work.resources.isNotEmpty) {
            final resource =
                work.resources[random.nextInt(work.resources.length)];
            session.toggleResource(work.url, resource.key);
          }
          break;
        case 5:
          if (work.resources.isNotEmpty) {
            final resource =
                work.resources[random.nextInt(work.resources.length)];
            session.setResource(work.url, resource.key, random.nextBool());
          }
          break;
        case 6:
          final kind = random.nextBool()
              ? WorkMediaKind.video
              : WorkMediaKind.image;
          session.toggleAuthorKind(
            authors[random.nextInt(authors.length)].secUid,
            kind,
          );
          break;
        case 7:
          session.setTerminalQuality(
            random.nextBool() ? QualityEdge.highest : QualityEdge.lowest,
          );
          break;
        case 8:
          session.toggleAuthorQuality(
            authors[random.nextInt(authors.length)].secUid,
          );
          break;
        case 9:
          if (work.behavesAsVideo && work.tiers.isNotEmpty) {
            session.setTier(
              work.url,
              work.tiers[random.nextInt(work.tiers.length)].url,
            );
          }
          break;
        case 10:
          if (random.nextBool()) {
            session.toggleAll();
          } else {
            session.setAll(
              random.nextBool() ? SelectionState.all : SelectionState.none,
            );
          }
          break;
        case 11:
          session.setAuthorResource(
            authors[random.nextInt(authors.length)].secUid,
            MediaType.values[random.nextInt(MediaType.values.length)],
            random.nextBool(),
          );
          break;
        case 12:
          session.setTerminalResource(
            MediaType.values[random.nextInt(MediaType.values.length)],
            random.nextBool(),
          );
          break;
        case 13:
          session.setTerminalKind(
            random.nextBool() ? WorkMediaKind.video : WorkMediaKind.image,
            random.nextBool() ? SelectionState.all : SelectionState.none,
          );
          break;
        case 14:
          session.setAuthorKind(
            authors[random.nextInt(authors.length)].secUid,
            random.nextBool() ? WorkMediaKind.video : WorkMediaKind.image,
            random.nextBool() ? SelectionState.all : SelectionState.none,
          );
          break;
      }

      final violations = SelectionInvariants.check(session);
      expect(
        violations,
        isEmpty,
        reason: 'op=$i index=$op url=${work.url}',
      );
    }
  });
}