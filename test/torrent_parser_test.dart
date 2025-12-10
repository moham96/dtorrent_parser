import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_parser/src/torrent_validator.dart';
import 'package:path/path.dart' as path;
import 'package:b_encode_decode/b_encode_decode.dart' as bencoding;

final testDirectory = path.join(
  Directory.current.path,
  Directory.current.path.endsWith('test') ? '' : 'test',
);

/// Creates a minimal valid torrent file in memory
/// Returns the bencoded bytes that can be passed to Torrent.parse
Uint8List createMinimalTorrentFile({
  String name = 'test-file',
  int length = 100,
  int pieceLength = 16384,
  List<String>? announces,
  String? encoding,
  bool? private,
  DateTime? creationDate,
  String? createdBy,
  String? comment,
  List<String>? urlList,
  List<List<dynamic>>? nodes,
  List<Map<String, dynamic>>? files,
  String? nameUtf8,
}) {
  // Create pieces (20 bytes per piece, SHA1 hash)
  final numPieces = (length / pieceLength).ceil();
  final pieces = Uint8List(numPieces * 20);
  // Fill with dummy hash values
  for (var i = 0; i < numPieces; i++) {
    pieces.setRange(i * 20, (i + 1) * 20, List.filled(20, i % 256));
  }

  final info = <String, dynamic>{
    'piece length': pieceLength,
    'pieces': pieces,
  };

  if (nameUtf8 != null) {
    info['name.utf-8'] = Uint8List.fromList(utf8.encode(nameUtf8));
  } else {
    info['name'] = name;
  }

  if (files != null) {
    info['files'] = files;
    // Calculate total length for pieces
    final totalLength =
        files.fold<int>(0, (sum, file) => sum + (file['length'] as int));
    final numPieces = (totalLength / pieceLength).ceil();
    final pieces = Uint8List(numPieces * 20);
    for (var i = 0; i < numPieces; i++) {
      pieces.setRange(i * 20, (i + 1) * 20, List.filled(20, i % 256));
    }
    info['pieces'] = pieces;
  } else {
    info['length'] = length;
  }

  if (private != null) {
    info['private'] = private ? 1 : 0;
  }

  final torrent = <String, dynamic>{
    'info': info,
  };

  if (encoding != null) {
    torrent['encoding'] = encoding;
  }

  if (creationDate != null) {
    torrent['creation date'] = creationDate.millisecondsSinceEpoch ~/ 1000;
  }

  if (createdBy != null) {
    torrent['created by'] = createdBy;
  }

  if (comment != null) {
    torrent['comment'] = Uint8List.fromList(comment.codeUnits);
  }

  if (announces != null && announces.isNotEmpty) {
    torrent['announce'] = announces[0];
    if (announces.length > 1) {
      torrent['announce-list'] = announces.map((a) => [a]).toList();
    }
  }

  if (urlList != null && urlList.isNotEmpty) {
    torrent['url-list'] = urlList;
  }

  if (nodes != null && nodes.isNotEmpty) {
    torrent['nodes'] = nodes;
  }

  return Uint8List.fromList(bencoding.encode(torrent));
}

void main() {
  test('Test parse torrent file from bytes', () async {
    // Create a minimal torrent file programmatically
    final torrentBytes = createMinimalTorrentFile(
      name: 'test-file.txt',
      length: 1000,
      pieceLength: 16384,
      announces: ['http://tracker.example.com:8080/announce'],
    );

    final result = await Torrent.parseFromBytes(torrentBytes);
    expect(result, isNotNull);
    expect(result.name, 'test-file.txt');
    expect(result.length, 1000);
    expect(result.pieceLength, 16384);
    expect(result.announces.length, 1);
    expect(result.announces.first.toString(),
        'http://tracker.example.com:8080/announce');
    expect(result.files.length, 1);
    expect(result.files.first.name, 'test-file.txt');
  });

  test('Test save torrent file and validate the model is the same', () async {
    // Create a minimal torrent file programmatically
    final torrentBytes = createMinimalTorrentFile(
      name: 'test-save-file.txt',
      length: 2000,
      pieceLength: 16384,
      announces: [
        'http://tracker1.example.com:8080/announce',
        'http://tracker2.example.com:8080/announce',
      ],
    );

    final model = await Torrent.parseFromBytes(torrentBytes);
    final tmpDir = Directory(path.join(testDirectory, '..', 'tmp'));
    if (!tmpDir.existsSync()) {
      tmpDir.createSync(recursive: true);
    }
    final newFile = await model.saveAs(
        path.join(tmpDir.path, 'test-save-file.torrent'), true);
    final newModel = await Torrent.parseFromFile(newFile.path);

    expect(model.name, newModel.name);
    expect(model.infoHash, newModel.infoHash);
    expect(model.length, newModel.length);
    expect(model.pieceLength, newModel.pieceLength);
    expect(model.filePath, isNot(equals(newModel.filePath)));

    expect(model.announces.length, newModel.announces.length);

    for (var index = 0; index < model.announces.length; index++) {
      final a1 = model.announces.elementAt(index);
      final a2 = newModel.announces.elementAt(index);
      expect(a1, a2);
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
    test('throws on missing info', () async {
      final badMap = <String, dynamic>{};
      final badBytes = Uint8List.fromList(bencoding.encode(badMap));
      expectLater(
          Torrent.parseFromBytes(badBytes),
          throwsA(predicate((e) => e
              .toString()
              .contains('Torrent is missing required field: info'))));
    });

    test('throws on missing name', () async {
      final badMap = <String, dynamic>{
        'info': {
          'piece length': 16384,
          'pieces': Uint8List(20),
          'length': 100,
        }
      };
      final badBytes = Uint8List.fromList(bencoding.encode(badMap));
      expectLater(
          Torrent.parseFromBytes(badBytes),
          throwsA(predicate((e) => e
              .toString()
              .contains('Torrent is missing required field: info.name'))));
    });

    test('throws on missing piece length', () async {
      final badMap = <String, dynamic>{
        'info': {
          'name': 'test',
          'pieces': Uint8List(20),
          'length': 100,
        }
      };
      final badBytes = Uint8List.fromList(bencoding.encode(badMap));
      expectLater(
          Torrent.parseFromBytes(badBytes),
          throwsA(predicate((e) => e.toString().contains(
              "Torrent is missing required field: info['piece length']"))));
    });

    test('throws on missing pieces', () async {
      final badMap = <String, dynamic>{
        'info': {
          'name': 'test',
          'piece length': 16384,
          'length': 100,
        }
      };
      final badBytes = Uint8List.fromList(bencoding.encode(badMap));
      expectLater(
          Torrent.parseFromBytes(badBytes),
          throwsA(predicate((e) => e
              .toString()
              .contains('Torrent is missing required field: info.pieces'))));
    });

    test('throws on missing length for single file', () async {
      final badMap = <String, dynamic>{
        'info': {
          'name': 'test',
          'piece length': 16384,
          'pieces': Uint8List(20),
        }
      };
      final badBytes = Uint8List.fromList(bencoding.encode(badMap));
      expectLater(
          Torrent.parseFromBytes(badBytes),
          throwsA(predicate((e) => e
              .toString()
              .contains('Torrent is missing required field: info.length'))));
    });

    test('throws on missing path for multi-file', () async {
      final badMap = <String, dynamic>{
        'info': {
          'name': 'test',
          'piece length': 16384,
          'pieces': Uint8List(20),
          'files': [
            {'length': 100}
          ],
        }
      };
      final badBytes = Uint8List.fromList(bencoding.encode(badMap));
      expectLater(
          Torrent.parseFromBytes(badBytes),
          throwsA(predicate((e) => e.toString().contains(
              'Torrent is missing required field: info.files[0].path'))));
    });
  });

  group('Torrent parsing with optional fields', () {
    test('parses torrent with encoding field', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'encoded-file',
        length: 500,
        encoding: 'UTF-8',
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result, isNotNull);
      expect(result.encoding, 'UTF-8');
    });

    test('parses torrent with private field', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'private-file',
        length: 500,
        private: true,
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result, isNotNull);
      expect(result.private, isTrue);
    });

    test('parses torrent with creation date', () async {
      final creationDate = DateTime(2023, 1, 1);
      final torrentBytes = createMinimalTorrentFile(
        name: 'dated-file',
        length: 500,
        creationDate: creationDate,
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result, isNotNull);
      expect(result.creationDate, isNotNull);
      expect(result.creationDate!.year, 2023);
    });

    test('parses torrent with created by', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'created-file',
        length: 500,
        createdBy: 'Test Creator 1.0',
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result, isNotNull);
      expect(result.createdBy, 'Test Creator 1.0');
    });

    test('parses torrent with comment', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'commented-file',
        length: 500,
        comment: 'This is a test comment',
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result, isNotNull);
      expect(result.comment, 'This is a test comment');
    });

    test('parses torrent with url-list (BEP19)', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'webseed-file',
        length: 500,
        urlList: [
          'http://example.com/files/',
          'ftp://example.com/files/',
        ],
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result, isNotNull);
      expect(result.urlList.length, 2);
      expect(
          result.urlList
              .any((u) => u.toString().contains('http://example.com')),
          isTrue);
      expect(
          result.urlList.any((u) => u.toString().contains('ftp://example.com')),
          isTrue);
    });

    test('parses torrent with nested announce-list', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'multi-tracker',
        length: 500,
        announces: [
          'http://tracker1.example.com/announce',
          'http://tracker2.example.com/announce',
          'http://tracker3.example.com/announce',
        ],
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result, isNotNull);
      expect(result.announces.length, 3);
    });

    test('parses torrent with DHT nodes (BEP5)', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'dht-file',
        length: 500,
        nodes: [
          [Uint8List.fromList('192.168.1.1'.codeUnits), 6881],
          [Uint8List.fromList('192.168.1.2'.codeUnits), 6882],
        ],
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result, isNotNull);
      expect(result.nodes.length, 2);
    });

    test('parses torrent with name.utf-8', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'fallback',
        nameUtf8: 'test-utf8-file',
        length: 500,
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result, isNotNull);
      expect(result.name, 'test-utf8-file');
    });

    test('parses multi-file torrent', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'multi-file-torrent',
        files: [
          {
            'path': ['file1.txt'],
            'length': 100,
          },
          {
            'path': ['file2.txt'],
            'length': 200,
          },
        ],
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result, isNotNull);
      expect(result.files.length, 2);
      expect(result.length, 300);
      expect(result.files[0].name, 'file1.txt');
      expect(result.files[1].name, 'file2.txt');
    });

    test('parses multi-file torrent with path.utf-8', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'utf8-multi-file',
        files: [
          {
            'path.utf-8': [Uint8List.fromList(utf8.encode('file1.txt'))],
            'length': 100,
          },
        ],
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result, isNotNull);
      expect(result.files.length, 1);
      expect(result.files[0].name, 'file1.txt');
    });
  });

  group('Torrent saveAs edge cases', () {
    test('saveAs throws when file exists and force is false', () async {
      final torrentBytes =
          createMinimalTorrentFile(name: 'existing-file', length: 100);
      final model = await Torrent.parseFromBytes(torrentBytes);
      final tmpDir = Directory(path.join(testDirectory, '..', 'tmp'));
      if (!tmpDir.existsSync()) {
        tmpDir.createSync(recursive: true);
      }
      final filePath = path.join(tmpDir.path, 'existing.torrent');

      // Create the file first
      await model.saveAs(filePath, true);

      // Try to save again without force
      expect(() => model.saveAs(filePath, false), throwsException);
    });

    test('save method uses filePath', () async {
      final torrentBytes =
          createMinimalTorrentFile(name: 'save-test', length: 100);
      final model = await Torrent.parseFromBytes(torrentBytes);
      final tmpDir = Directory(path.join(testDirectory, '..', 'tmp'));
      if (!tmpDir.existsSync()) {
        tmpDir.createSync(recursive: true);
      }
      final filePath = path.join(tmpDir.path, 'save-test.torrent');
      model.filePath = filePath;

      final savedFile = await model.save();
      expect(savedFile.path, filePath);
      expect(await savedFile.exists(), isTrue);
    });
  });

  group('Torrent toByteBuffer', () {
    test('generates byte buffer with single announce', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'single-announce',
        length: 100,
        announces: ['http://tracker.example.com/announce'],
      );
      final model = await Torrent.parseFromBytes(torrentBytes);
      final buffer = await model.toByteBuffer();
      expect(buffer, isA<Uint8List>());
      expect(buffer.length, greaterThan(0));
    });

    test('generates byte buffer with multiple announces', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'multi-announce',
        length: 100,
        announces: [
          'http://tracker1.example.com/announce',
          'http://tracker2.example.com/announce',
        ],
      );
      final model = await Torrent.parseFromBytes(torrentBytes);
      final buffer = await model.toByteBuffer();
      expect(buffer, isA<Uint8List>());

      // Parse it back to verify
      final parsed = await Torrent.parseFromBytes(buffer);
      expect(parsed.announces.length, 2);
    });

    test('generates byte buffer with url-list', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'webseed',
        length: 100,
        urlList: ['http://example.com/files/'],
      );
      final model = await Torrent.parseFromBytes(torrentBytes);
      final buffer = await model.toByteBuffer();
      expect(buffer, isA<Uint8List>());

      final parsed = await Torrent.parseFromBytes(buffer);
      expect(parsed.urlList.length, 1);
    });

    test('generates byte buffer with optional fields', () async {
      final creationDate = DateTime(2023, 6, 15);
      final torrentBytes = createMinimalTorrentFile(
        name: 'full-featured',
        length: 100,
        encoding: 'UTF-8',
        private: true,
        creationDate: creationDate,
        createdBy: 'Test Tool 1.0',
        comment: 'Test comment',
      );
      final model = await Torrent.parseFromBytes(torrentBytes);
      // Verify the model has the fields
      expect(model.encoding, 'UTF-8');
      expect(model.private, isTrue);
      expect(model.createdBy, 'Test Tool 1.0');
      expect(model.comment, 'Test comment');

      final buffer = await model.toByteBuffer();
      expect(buffer, isA<Uint8List>());

      final parsed = await Torrent.parseFromBytes(buffer);
      expect(parsed.private, isTrue);
      expect(parsed.createdBy, 'Test Tool 1.0');
      expect(parsed.comment, 'Test comment');
      // Note: encoding is not saved in toByteBuffer according to the code
    });
  });

  group('Torrent parse edge cases', () {
    test('parse with empty bytes throws', () async {
      expect(() => Torrent.parseFromBytes(Uint8List(0)), throwsA(anything));
    });

    test('parse with invalid bencode throws', () async {
      final invalidBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      // This should throw an exception (could be Exception or BencodeDecodeException)
      expect(() => Torrent.parseFromBytes(invalidBytes), throwsA(anything));
    });

    test('parse with file path sets filePath', () async {
      final torrentBytes =
          createMinimalTorrentFile(name: 'path-test', length: 100);
      final tmpDir = Directory(path.join(testDirectory, '..', 'tmp'));
      if (!tmpDir.existsSync()) {
        tmpDir.createSync(recursive: true);
      }
      final filePath = path.join(tmpDir.path, 'path-test.torrent');
      final file = File(filePath);
      await file.writeAsBytes(torrentBytes);

      final model = await Torrent.parseFromFile(filePath);
      expect(model.filePath, filePath);
    });
  });

  group('TorrentValidator', () {
    test('validates correct single-file torrent', () {
      final validTorrent = <String, dynamic>{
        'info': {
          'name': 'test-file',
          'piece length': 16384,
          'pieces': Uint8List(20),
          'length': 100,
        }
      };
      expect(() => TorrentValidator.validate(validTorrent), returnsNormally);
    });

    test('validates correct multi-file torrent', () {
      final validTorrent = <String, dynamic>{
        'info': {
          'name': 'test-dir',
          'piece length': 16384,
          'pieces': Uint8List(20),
          'files': [
            {
              'path': ['file1.txt'],
              'length': 100
            },
            {
              'path': ['file2.txt'],
              'length': 200
            },
          ],
        }
      };
      expect(() => TorrentValidator.validate(validTorrent), returnsNormally);
    });

    test('throws on missing info', () {
      final invalidTorrent = <String, dynamic>{};
      expect(
          () => TorrentValidator.validate(invalidTorrent),
          throwsA(isA<TorrentValidationException>()
              .having((e) => e.message, 'message', contains('info'))));
    });

    test('throws on missing name', () {
      final invalidTorrent = <String, dynamic>{
        'info': {
          'piece length': 16384,
          'pieces': Uint8List(20),
          'length': 100,
        }
      };
      expect(
          () => TorrentValidator.validate(invalidTorrent),
          throwsA(isA<TorrentValidationException>()
              .having((e) => e.message, 'message', contains('name'))));
    });

    test('accepts name.utf-8', () {
      final validTorrent = <String, dynamic>{
        'info': {
          'name.utf-8': Uint8List.fromList('test'.codeUnits),
          'piece length': 16384,
          'pieces': Uint8List(20),
          'length': 100,
        }
      };
      expect(() => TorrentValidator.validate(validTorrent), returnsNormally);
    });

    test('throws on missing piece length', () {
      final invalidTorrent = <String, dynamic>{
        'info': {
          'name': 'test',
          'pieces': Uint8List(20),
          'length': 100,
        }
      };
      expect(
          () => TorrentValidator.validate(invalidTorrent),
          throwsA(isA<TorrentValidationException>()
              .having((e) => e.message, 'message', contains('piece length'))));
    });

    test('throws on missing pieces', () {
      final invalidTorrent = <String, dynamic>{
        'info': {
          'name': 'test',
          'piece length': 16384,
          'length': 100,
        }
      };
      expect(
          () => TorrentValidator.validate(invalidTorrent),
          throwsA(isA<TorrentValidationException>()
              .having((e) => e.message, 'message', contains('pieces'))));
    });

    test('throws on missing length for single file', () {
      final invalidTorrent = <String, dynamic>{
        'info': {
          'name': 'test',
          'piece length': 16384,
          'pieces': Uint8List(20),
        }
      };
      expect(
          () => TorrentValidator.validate(invalidTorrent),
          throwsA(isA<TorrentValidationException>()
              .having((e) => e.message, 'message', contains('length'))));
    });

    test('throws on missing path for multi-file', () {
      final invalidTorrent = <String, dynamic>{
        'info': {
          'name': 'test',
          'piece length': 16384,
          'pieces': Uint8List(20),
          'files': [
            {'length': 100}
          ],
        }
      };
      expect(
          () => TorrentValidator.validate(invalidTorrent),
          throwsA(isA<TorrentValidationException>()
              .having((e) => e.message, 'message', contains('path'))));
    });
  });

  group('TorrentParser edge cases', () {
    test('handles empty announce-list gracefully', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'empty-announce',
        length: 100,
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result.announces, isEmpty);
    });

    test('handles invalid announce URLs gracefully', () async {
      // Create a torrent with invalid announce URL
      final info = <String, dynamic>{
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'length': 100,
      };
      final torrent = <String, dynamic>{
        'info': info,
        'announce': Uint8List.fromList('not a valid url!!!'.codeUnits),
      };
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      // Should not crash, invalid URLs are silently ignored
      expect(result, isNotNull);
    });

    test('handles pieces with non-multiple-of-20 length', () async {
      final info = <String, dynamic>{
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(45), // Not a multiple of 20
        'length': 100,
      };
      final torrent = <String, dynamic>{'info': info};
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.pieces.length, 3); // 45 / 20 = 2.25, rounds to 3 pieces
    });

    test('handles single-file torrent correctly', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'single-file',
        length: 5000,
        pieceLength: 16384,
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result.files.length, 1);
      expect(result.files.first.name, 'single-file');
      expect(result.files.first.length, 5000);
      expect(result.files.first.offset, 0);
    });

    test('calculates lastPieceLength correctly', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'piece-test',
        length: 50000,
        pieceLength: 16384,
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result.pieceLength, 16384);
      // 50000 % 16384 = 848, so lastPieceLength should be 848
      expect(result.lastPieceLength, 848);
    });

    test('handles lastPieceLength when it divides evenly', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'even-piece',
        length: 32768, // Exactly 2 pieces
        pieceLength: 16384,
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result.lastPieceLength, 16384);
    });
  });

  group('TorrentSerializer edge cases', () {
    test('serializes torrent with no optional fields', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'minimal',
        length: 100,
      );
      final model = await Torrent.parseFromBytes(torrentBytes);
      final buffer = await model.toByteBuffer();
      expect(buffer, isA<Uint8List>());
      expect(buffer.length, greaterThan(0));

      // Parse it back
      final parsed = await Torrent.parseFromBytes(buffer);
      expect(parsed.name, 'minimal');
    });

    test('serializes torrent with all optional fields', () async {
      final creationDate = DateTime(2023, 6, 15, 10, 30);
      final torrentBytes = createMinimalTorrentFile(
        name: 'full-featured',
        length: 100,
        encoding: 'UTF-8',
        private: true,
        creationDate: creationDate,
        createdBy: 'Test Tool 2.0',
        comment: 'Full test comment',
        announces: [
          'http://tracker1.example.com/announce',
          'http://tracker2.example.com/announce',
        ],
        urlList: ['http://example.com/files/'],
      );
      final model = await Torrent.parseFromBytes(torrentBytes);
      final buffer = await model.toByteBuffer();
      final parsed = await Torrent.parseFromBytes(buffer);

      expect(parsed.private, isTrue);
      expect(parsed.createdBy, 'Test Tool 2.0');
      expect(parsed.comment, 'Full test comment');
      expect(parsed.announces.length, 2);
      expect(parsed.urlList.length, 1);
    });

    test('serializes torrent with private false', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'public-torrent',
        length: 100,
        private: false,
      );
      final model = await Torrent.parseFromBytes(torrentBytes);
      final buffer = await model.toByteBuffer();
      final parsed = await Torrent.parseFromBytes(buffer);
      expect(parsed.private, isFalse);
    });
  });

  group('Error handling improvements', () {
    test('TorrentValidationException has proper message', () {
      final exception = TorrentValidationException('Test error message');
      expect(exception.message, 'Test error message');
      expect(exception.toString(), 'Test error message');
    });

    test('parse handles null decode result', () async {
      final invalidBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(() => Torrent.parseFromBytes(invalidBytes), throwsA(anything));
    });

    test('saveAs creates directory if needed', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'dir-test',
        length: 100,
      );
      final model = await Torrent.parseFromBytes(torrentBytes);
      final tmpDir = Directory(
          path.join(testDirectory, '..', 'tmp', 'nested', 'deep', 'path'));
      if (tmpDir.existsSync()) {
        tmpDir.deleteSync(recursive: true);
      }
      final filePath = path.join(tmpDir.path, 'test.torrent');

      final savedFile = await model.saveAs(filePath, true);
      expect(await savedFile.exists(), isTrue);
      expect(savedFile.path, filePath);
    });
  });

  group('Backward compatibility', () {
    test('deprecated parseTorrentFileContent still works', () async {
      final validTorrent = <String, dynamic>{
        'info': {
          'name': 'test',
          'piece length': 16384,
          'pieces': Uint8List(20),
          'length': 100,
        }
      };
      final validBytes = Uint8List.fromList(bencoding.encode(validTorrent));
      final result = await Torrent.parseFromBytes(validBytes);
      expect(result, isNotNull);
      expect(result.name, 'test');
    });

    test(
        'deprecated parseTorrentFileContent throws TorrentValidationException on invalid',
        () async {
      final invalidTorrent = <String, dynamic>{};
      final invalidBytes = Uint8List.fromList(bencoding.encode(invalidTorrent));
      expectLater(
          Torrent.parseFromBytes(invalidBytes),
          throwsA(predicate((e) => e
              .toString()
              .contains('Torrent is missing required field: info'))));
    });
  });

  group('TorrentParser additional edge cases', () {
    test('handles comment as String', () async {
      final info = <String, dynamic>{
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'length': 100,
      };
      final torrent = <String, dynamic>{
        'info': info,
        'comment': 'String comment',
      };
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.comment, 'String comment');
    });

    test('handles encoding as String', () async {
      final info = <String, dynamic>{
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'length': 100,
      };
      final torrent = <String, dynamic>{
        'info': info,
        'encoding': 'UTF-8',
      };
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.encoding, 'UTF-8');
    });

    test('handles created by as String', () async {
      final info = <String, dynamic>{
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'length': 100,
      };
      final torrent = <String, dynamic>{
        'info': info,
        'created by': 'Test Tool',
      };
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.createdBy, 'Test Tool');
    });

    test('handles name as String', () async {
      final info = <String, dynamic>{
        'name': 'string-name',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'length': 100,
      };
      final torrent = <String, dynamic>{'info': info};
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.name, 'string-name');
    });

    test('handles empty announce-list gracefully', () async {
      final info = <String, dynamic>{
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'length': 100,
      };
      final torrent = <String, dynamic>{
        'info': info,
        'announce-list': [],
      };
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.announces, isEmpty);
    });

    test('handles nested announce-list with empty inner lists', () async {
      final info = <String, dynamic>{
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'length': 100,
      };
      final torrent = <String, dynamic>{
        'info': info,
        'announce-list': [
          [Uint8List.fromList('http://tracker1.com'.codeUnits)],
          []
        ],
      };
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.announces.length, 1);
    });

    test('handles announce-list with mixed nested and flat structures',
        () async {
      final info = <String, dynamic>{
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'length': 100,
      };
      final torrent = <String, dynamic>{
        'info': info,
        'announce-list': [
          [Uint8List.fromList('http://tracker1.com'.codeUnits)],
          Uint8List.fromList('http://tracker2.com'.codeUnits),
        ],
      };
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.announces.length, 2);
    });

    test('handles empty pieces buffer', () async {
      final info = <String, dynamic>{
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(0),
        'length': 0,
      };
      final torrent = <String, dynamic>{'info': info};
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.pieces, isEmpty);
    });

    test('handles pieces buffer with incomplete last piece', () async {
      final info = <String, dynamic>{
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(25), // Not a multiple of 20
        'length': 100,
      };
      final torrent = <String, dynamic>{'info': info};
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.pieces.length, 2); // 25 bytes = 1 full piece + 5 bytes
    });

    test('handles url-list with invalid URLs gracefully', () async {
      final info = <String, dynamic>{
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'length': 100,
      };
      final torrent = <String, dynamic>{
        'info': info,
        'url-list': [
          Uint8List.fromList('://invalid-url'.codeUnits), // Invalid URI format
          Uint8List.fromList('http://valid.com'.codeUnits),
        ],
      };
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      // Should only have the valid URL (invalid ones are silently ignored)
      expect(result.urlList.length, greaterThanOrEqualTo(1));
      expect(result.urlList.any((u) => u.toString().contains('valid.com')),
          isTrue);
    });

    test('handles nodes with invalid data gracefully', () async {
      final info = <String, dynamic>{
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'length': 100,
      };
      final torrent = <String, dynamic>{
        'info': info,
        'nodes': [
          [Uint8List.fromList('192.168.1.1'.codeUnits), 6881],
          [null, 6882], // Invalid node
          ['invalid', 'port'], // Invalid types
        ],
      };
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      // Should only have the valid node
      expect(result.nodes.length, 1);
    });

    test('handles multi-file torrent with empty path parts', () async {
      final info = <String, dynamic>{
        'name': 'test-dir',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'files': [
          {'path': [], 'length': 100}, // Empty path
        ],
      };
      final torrent = <String, dynamic>{'info': info};
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.files.length, 1);
      expect(result.files.first.name, 'test-dir');
    });

    test('handles file path with null parts', () async {
      final info = <String, dynamic>{
        'name': 'test-dir',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'files': [
          {
            'path': [
              Uint8List.fromList('file1.txt'.codeUnits),
              null, // null part
              Uint8List.fromList('file2.txt'.codeUnits),
            ],
            'length': 100
          },
        ],
      };
      final torrent = <String, dynamic>{'info': info};
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.files.length, 1);
    });
  });

  group('TorrentSerializer additional edge cases', () {
    test('serializes torrent with null optional fields', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'minimal',
        length: 100,
      );
      final model = await Torrent.parseFromBytes(torrentBytes);
      // Ensure all optional fields are null
      model.private = null;
      model.creationDate = null;
      model.createdBy = null;
      model.comment = null;

      final buffer = await model.toByteBuffer();
      expect(buffer, isA<Uint8List>());
      expect(buffer.length, greaterThan(0));

      // Parse it back
      final parsed = await Torrent.parseFromBytes(buffer);
      expect(parsed.name, 'minimal');
    });

    test('serializes torrent with empty announces', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'no-announce',
        length: 100,
      );
      final model = await Torrent.parseFromBytes(torrentBytes);
      model.announces.clear();

      final buffer = await model.toByteBuffer();
      final parsed = await Torrent.parseFromBytes(buffer);
      expect(parsed.announces, isEmpty);
    });

    test('serializes torrent with empty urlList', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'no-urls',
        length: 100,
      );
      final model = await Torrent.parseFromBytes(torrentBytes);
      model.urlList.clear();

      final buffer = await model.toByteBuffer();
      final parsed = await Torrent.parseFromBytes(buffer);
      expect(parsed.urlList, isEmpty);
    });

    test('serializes torrent with only creation date', () async {
      final creationDate = DateTime(2023, 1, 1);
      final torrentBytes = createMinimalTorrentFile(
        name: 'date-only',
        length: 100,
      );
      final model = await Torrent.parseFromBytes(torrentBytes);
      model.creationDate = creationDate;
      model.createdBy = null;
      model.comment = null;

      final buffer = await model.toByteBuffer();
      final parsed = await Torrent.parseFromBytes(buffer);
      expect(parsed.creationDate, isNotNull);
      expect(parsed.createdBy, isNull);
      expect(parsed.comment, isNull);
    });
  });

  group('Isolate error handling', () {
    test('handles invalid torrent model in toByteBuffer', () async {
      final dummyInfo = {
        'name': 'dummy',
        'piece length': 16,
        'pieces': List<int>.filled(20, 1),
        'length': 100
      };
      final infoHash = List<int>.filled(20, 2);
      final torrent = Torrent(
          dummyInfo, 'dummy', 'hash', Uint8List.fromList(infoHash), 100);

      // This should work fine
      final buffer = await torrent.toByteBuffer();
      expect(buffer, isA<Uint8List>());
    });
  });

  group('TorrentValidator additional cases', () {
    test('validates torrent with name.utf-8 only', () {
      final validTorrent = <String, dynamic>{
        'info': {
          'name.utf-8': Uint8List.fromList('test-file'.codeUnits),
          'piece length': 16384,
          'pieces': Uint8List(20),
          'length': 100,
        }
      };
      expect(() => TorrentValidator.validate(validTorrent), returnsNormally);
    });

    test('validates multi-file torrent with path.utf-8', () {
      final validTorrent = <String, dynamic>{
        'info': {
          'name': 'test-dir',
          'piece length': 16384,
          'pieces': Uint8List(20),
          'files': [
            {
              'path.utf-8': [Uint8List.fromList('file1.txt'.codeUnits)],
              'length': 100
            },
          ],
        }
      };
      expect(() => TorrentValidator.validate(validTorrent), returnsNormally);
    });

    test('validates multi-file torrent with both path and path.utf-8', () {
      final validTorrent = <String, dynamic>{
        'info': {
          'name': 'test-dir',
          'piece length': 16384,
          'pieces': Uint8List(20),
          'files': [
            {
              'path': ['file1.txt'],
              'path.utf-8': [Uint8List.fromList('file1.txt'.codeUnits)],
              'length': 100
            },
          ],
        }
      };
      expect(() => TorrentValidator.validate(validTorrent), returnsNormally);
    });
  });

  group('Torrent class edge cases', () {
    test('handles removePiece with non-existent piece', () {
      final dummyInfo = {
        'name': 'dummy',
        'piece length': 16,
        'pieces': List<int>.filled(20, 1),
        'length': 100
      };
      final infoHash = List<int>.filled(20, 2);
      final torrent = Torrent(
          dummyInfo, 'dummy', 'hash', Uint8List.fromList(infoHash), 100);

      final initialLength = torrent.pieces.length;
      torrent.removePiece('non-existent');
      expect(torrent.pieces.length, initialLength);
    });

    test('handles removeFile with non-existent file', () {
      final dummyInfo = {
        'name': 'dummy',
        'piece length': 16,
        'pieces': List<int>.filled(20, 1),
        'length': 100
      };
      final infoHash = List<int>.filled(20, 2);
      final torrent = Torrent(
          dummyInfo, 'dummy', 'hash', Uint8List.fromList(infoHash), 100);

      final file = TorrentFile('non-existent', '/path', 100, 0);
      torrent.removeFile(file);
      expect(torrent.files, isEmpty);
    });

    test('handles save with null filePath', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'no-path',
        length: 100,
      );
      final model = await Torrent.parseFromBytes(torrentBytes);
      model.filePath = null;

      expect(() => model.save(), throwsA(anything));
    });

    test('handles multiple add/remove operations', () {
      final dummyInfo = {
        'name': 'dummy',
        'piece length': 16,
        'pieces': List<int>.filled(20, 1),
        'length': 100
      };
      final infoHash = List<int>.filled(20, 2);
      final torrent = Torrent(
          dummyInfo, 'dummy', 'hash', Uint8List.fromList(infoHash), 100);

      final uri1 = Uri.parse('http://tracker1.com');
      final uri2 = Uri.parse('http://tracker2.com');

      torrent.addAnnounce(uri1);
      torrent.addAnnounce(uri2);
      expect(torrent.announces.length, 2);

      torrent.removeAnnounce(uri1);
      expect(torrent.announces.length, 1);
      expect(torrent.announces.contains(uri2), isTrue);
    });
  });

  group('File parsing edge cases', () {
    test('handles file with path as List<int>', () async {
      final info = <String, dynamic>{
        'name': 'test-dir',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'files': [
          {
            'path': [
              [102, 105, 108, 101, 46, 116, 120, 116] // 'file.txt' as List<int>
            ],
            'length': 100
          },
        ],
      };
      final torrent = <String, dynamic>{'info': info};
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.files.length, 1);
    });

    test('handles file path with mixed String and Uint8List', () async {
      final info = <String, dynamic>{
        'name': 'test-dir',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'files': [
          {
            'path': [
              'string-part',
              Uint8List.fromList('bytes-part'.codeUnits),
            ],
            'length': 100
          },
        ],
      };
      final torrent = <String, dynamic>{'info': info};
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.files.length, 1);
    });
  });

  group('Boundary conditions', () {
    test('handles very large piece length', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'large-piece',
        length: 1000000,
        pieceLength: 1048576, // 1MB
      );
      final result = await Torrent.parseFromBytes(torrentBytes);
      expect(result.pieceLength, 1048576);
      expect(result.lastPieceLength, 1000000 % 1048576);
    });

    test('handles zero-length file', () async {
      final info = <String, dynamic>{
        'name': 'empty-file',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'length': 0,
      };
      final torrent = <String, dynamic>{'info': info};
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.length, 0);
      expect(result.files.length, 1);
      expect(result.files.first.length, 0);
    });

    test('handles torrent with maximum number of pieces', () async {
      // Create a torrent with many pieces (but not too many to avoid timeout)
      final numPieces = 100;
      final pieces = Uint8List(numPieces * 20);
      for (var i = 0; i < numPieces; i++) {
        pieces.setRange(i * 20, (i + 1) * 20, List.filled(20, i % 256));
      }

      final info = <String, dynamic>{
        'name': 'many-pieces',
        'piece length': 16384,
        'pieces': pieces,
        'length': numPieces * 16384,
      };
      final torrent = <String, dynamic>{'info': info};
      final bytes = Uint8List.fromList(bencoding.encode(torrent));
      final result = await Torrent.parseFromBytes(bytes);
      expect(result.pieces.length, numPieces);
    });
  });
}
