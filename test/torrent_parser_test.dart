import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
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

    final result = await Torrent.parse(torrentBytes);
    expect(result, isNotNull);
    expect(result!.name, 'test-file.txt');
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

    final model = await Torrent.parse(torrentBytes);
    final tmpDir = Directory(path.join(testDirectory, '..', 'tmp'));
    if (!tmpDir.existsSync()) {
      tmpDir.createSync(recursive: true);
    }
    final newFile = await model.saveAs(
        path.join(tmpDir.path, 'test-save-file.torrent'), true);
    final newModel = await Torrent.parse(newFile.path);

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
    test('throws on missing info', () {
      final badMap = <String, dynamic>{};
      expect(() => parseTorrentFileContent(badMap),
          throwsA(isA<AssertionError>()));
    });

    test('throws on missing name', () {
      final badMap = <String, dynamic>{
        'info': {
          'piece length': 16384,
          'pieces': Uint8List(20),
          'length': 100,
        }
      };
      expect(() => parseTorrentFileContent(badMap),
          throwsA(isA<AssertionError>()));
    });

    test('throws on missing piece length', () {
      final badMap = <String, dynamic>{
        'info': {
          'name': 'test',
          'pieces': Uint8List(20),
          'length': 100,
        }
      };
      expect(() => parseTorrentFileContent(badMap),
          throwsA(isA<AssertionError>()));
    });

    test('throws on missing pieces', () {
      final badMap = <String, dynamic>{
        'info': {
          'name': 'test',
          'piece length': 16384,
          'length': 100,
        }
      };
      expect(() => parseTorrentFileContent(badMap),
          throwsA(isA<AssertionError>()));
    });

    test('throws on missing length for single file', () {
      final badMap = <String, dynamic>{
        'info': {
          'name': 'test',
          'piece length': 16384,
          'pieces': Uint8List(20),
        }
      };
      expect(() => parseTorrentFileContent(badMap),
          throwsA(isA<AssertionError>()));
    });

    test('throws on missing path for multi-file', () {
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
      expect(() => parseTorrentFileContent(badMap),
          throwsA(isA<AssertionError>()));
    });
  });

  group('Torrent parsing with optional fields', () {
    test('parses torrent with encoding field', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'encoded-file',
        length: 500,
        encoding: 'UTF-8',
      );
      final result = await Torrent.parse(torrentBytes);
      expect(result, isNotNull);
      expect(result!.encoding, 'UTF-8');
    });

    test('parses torrent with private field', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'private-file',
        length: 500,
        private: true,
      );
      final result = await Torrent.parse(torrentBytes);
      expect(result, isNotNull);
      expect(result!.private, isTrue);
    });

    test('parses torrent with creation date', () async {
      final creationDate = DateTime(2023, 1, 1);
      final torrentBytes = createMinimalTorrentFile(
        name: 'dated-file',
        length: 500,
        creationDate: creationDate,
      );
      final result = await Torrent.parse(torrentBytes);
      expect(result, isNotNull);
      expect(result!.creationDate, isNotNull);
      expect(result.creationDate!.year, 2023);
    });

    test('parses torrent with created by', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'created-file',
        length: 500,
        createdBy: 'Test Creator 1.0',
      );
      final result = await Torrent.parse(torrentBytes);
      expect(result, isNotNull);
      expect(result!.createdBy, 'Test Creator 1.0');
    });

    test('parses torrent with comment', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'commented-file',
        length: 500,
        comment: 'This is a test comment',
      );
      final result = await Torrent.parse(torrentBytes);
      expect(result, isNotNull);
      expect(result!.comment, 'This is a test comment');
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
      final result = await Torrent.parse(torrentBytes);
      expect(result, isNotNull);
      expect(result!.urlList.length, 2);
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
      final result = await Torrent.parse(torrentBytes);
      expect(result, isNotNull);
      expect(result!.announces.length, 3);
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
      final result = await Torrent.parse(torrentBytes);
      expect(result, isNotNull);
      expect(result!.nodes.length, 2);
    });

    test('parses torrent with name.utf-8', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'fallback',
        nameUtf8: 'test-utf8-file',
        length: 500,
      );
      final result = await Torrent.parse(torrentBytes);
      expect(result, isNotNull);
      expect(result!.name, 'test-utf8-file');
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
      final result = await Torrent.parse(torrentBytes);
      expect(result, isNotNull);
      expect(result!.files.length, 2);
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
      final result = await Torrent.parse(torrentBytes);
      expect(result, isNotNull);
      expect(result!.files.length, 1);
      expect(result.files[0].name, 'file1.txt');
    });
  });

  group('Torrent saveAs edge cases', () {
    test('saveAs throws when file exists and force is false', () async {
      final torrentBytes =
          createMinimalTorrentFile(name: 'existing-file', length: 100);
      final model = await Torrent.parse(torrentBytes);
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
      final model = await Torrent.parse(torrentBytes);
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
      final model = await Torrent.parse(torrentBytes);
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
      final model = await Torrent.parse(torrentBytes);
      final buffer = await model.toByteBuffer();
      expect(buffer, isA<Uint8List>());

      // Parse it back to verify
      final parsed = await Torrent.parse(buffer);
      expect(parsed.announces.length, 2);
    });

    test('generates byte buffer with url-list', () async {
      final torrentBytes = createMinimalTorrentFile(
        name: 'webseed',
        length: 100,
        urlList: ['http://example.com/files/'],
      );
      final model = await Torrent.parse(torrentBytes);
      final buffer = await model.toByteBuffer();
      expect(buffer, isA<Uint8List>());

      final parsed = await Torrent.parse(buffer);
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
      final model = await Torrent.parse(torrentBytes);
      // Verify the model has the fields
      expect(model.encoding, 'UTF-8');
      expect(model.private, isTrue);
      expect(model.createdBy, 'Test Tool 1.0');
      expect(model.comment, 'Test comment');

      final buffer = await model.toByteBuffer();
      expect(buffer, isA<Uint8List>());

      final parsed = await Torrent.parse(buffer);
      expect(parsed.private, isTrue);
      expect(parsed.createdBy, 'Test Tool 1.0');
      expect(parsed.comment, 'Test comment');
      // Note: encoding is not saved in toByteBuffer according to the code
    });
  });

  group('Torrent parse edge cases', () {
    test('parse with empty bytes throws', () async {
      expect(() => Torrent.parse(Uint8List(0)), throwsA(anything));
    });

    test('parse with invalid bencode throws', () async {
      final invalidBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      // This should throw an exception (could be Exception or BencodeDecodeException)
      expect(() => Torrent.parse(invalidBytes), throwsA(anything));
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

      final model = await Torrent.parse(filePath);
      expect(model.filePath, filePath);
    });
  });
}
