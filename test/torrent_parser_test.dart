import 'dart:io';

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
}
