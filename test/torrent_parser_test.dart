import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:path/path.dart' as path;

final testDirectory = path.join(
  Directory.current.path,
  Directory.current.path.endsWith('test') ? '' : 'test',
);

var torrentsPath =
    path.canonicalize(path.join(testDirectory, '..', '..', '..', 'torrents'));
void main() {
  /// Magnet URI id：DD8255ECDC7CA55FB0BBF81323D87062DB1F6D1C
  test('Test parse torrent file from a file', () async {
    // If the file is changed, please remember to modify the verification information below accordingly.
    var result =
        await Torrent.parse(path.join(torrentsPath, 'big-buck-bunny.torrent'));
    assert(result.infoHash == 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c');
    assert(result.announces.length == 8);
    assert(result.files.length == 3);
    assert(result.length == 276445467);
  });

  test('Test save torrent file and validate the model is the same', () async {
    var model =
        await Torrent.parse(path.join(torrentsPath, 'big-buck-bunny.torrent'));
    var newFile = await model.saveAs(
        path.join(testDirectory, '..', 'tmp', 'big-buck-bunny.torrent'), true);
    var newModel = await Torrent.parse(newFile.path);

    assert(model.name == newModel.name);
    assert(model.infoHash == newModel.infoHash);
    assert(model.length == newModel.length);
    assert(model.pieceLength == newModel.pieceLength);
    assert(model.filePath != newModel.filePath);

    assert(model.announces.length == newModel.announces.length);

    for (var index = 0; index < model.announces.length; index++) {
      var a1 = model.announces.elementAt(index);
      var a2 = newModel.announces.elementAt(index);
      assert(a1 == a2);
    }
  });

  group('TorrentFile', () {
    test('Constructor and properties', () {
      final file = TorrentFile('file1.txt', '/some/path/file1.txt', 1234, 0);
      expect(file.name, 'file1.txt');
      expect(file.path, '/some/path/file1.txt');
      expect(file.length, 1234);
      expect(file.offset, 0);
      expect(file.end, 1234);
    });

    test('toJson returns correct JSON', () {
      final file = TorrentFile('file2.txt', '/another/file2.txt', 5678, 100);
      final json = file.toJson();
      expect(json, contains('"length":5678'));
      expect(json, contains('"path":"/another/file2.txt"'));
    });

    test('toString returns expected string', () {
      final file = TorrentFile('file3.txt', '/p/file3.txt', 42, 10);
      expect(file.toString(), contains('file3.txt'));
      expect(file.toString(), contains('/p/file3.txt'));
      expect(file.toString(), contains('42'));
      expect(file.toString(), contains('10'));
    });
  });

  group('Torrent class direct usage', () {
    final dummyInfo = {
      'name': 'dummy',
      'piece length': 16,
      'pieces': List<int>.filled(20, 1),
      'length': 100
    };
    final infoHash = List<int>.filled(20, 2);
    final torrent =
        Torrent(dummyInfo, 'dummy', 'hash', Uint8List.fromList(infoHash), 100);

    test('add/remove announces', () {
      final uri = Uri.parse('http://tracker');
      expect(torrent.announces.length, 0);
      expect(torrent.addAnnounce(uri), true);
      expect(torrent.announces.contains(uri), true);
      expect(torrent.addAnnounce(uri), false); // already added
      expect(torrent.removeAnnounce(uri), true);
      expect(torrent.announces.contains(uri), false);
    });

    test('add/remove urlList', () {
      final uri = Uri.parse('http://webseed');
      expect(torrent.urlList.length, 0);
      expect(torrent.addURL(uri), true);
      expect(torrent.urlList.contains(uri), true);
      expect(torrent.addURL(uri), false);
      expect(torrent.removeURL(uri), true);
      expect(torrent.urlList.contains(uri), false);
    });

    test('add/remove files', () {
      final file = TorrentFile('f', '/f', 1, 0);
      expect(torrent.files.length, 0);
      torrent.addFile(file);
      expect(torrent.files.length, 1);
      torrent.removeFile(file);
      expect(torrent.files.length, 0);
    });

    test('add/remove pieces', () {
      expect(torrent.pieces.length, 0);
      torrent.addPiece('abc');
      expect(torrent.pieces, contains('abc'));
      torrent.removePiece('abc');
      expect(torrent.pieces, isNot(contains('abc')));
    });

    test('toString returns expected', () {
      expect(torrent.toString(), contains('Torrent Model'));
      expect(torrent.toString(), contains('dummy'));
      expect(torrent.toString(), contains('hash'));
    });
  });

  group('Torrent edge cases and errors', () {
    test('TorrentFile toJson with empty path', () {
      final file = TorrentFile('empty', '', 0, 0);
      expect(file.toJson(), contains('"length":0'));
      expect(file.toJson(), contains('"path":""'));
    });

    test('Torrent saveAs throws on null path', () async {
      final dummyInfo = {
        'name': 'dummy',
        'piece length': 16,
        'pieces': List<int>.filled(20, 1),
        'length': 100
      };
      final infoHash = List<int>.filled(20, 2);
      final torrent = Torrent(
          dummyInfo, 'dummy', 'hash', Uint8List.fromList(infoHash), 100);
      expect(() => torrent.saveAs(null), throwsException);
    });
  });

  group('parseTorrentFileContent', () {
    test('throws on missing info', () {
      final badMap = <String, dynamic>{};
      expect(() => parseTorrentFileContent(badMap),
          throwsA(isA<AssertionError>()));
    });
  });
}
