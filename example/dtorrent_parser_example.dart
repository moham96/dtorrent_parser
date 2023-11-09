import 'dart:io';

import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:path/path.dart' as path;

var scriptDir = path.dirname(Platform.script.path);
var torrentsPath =
    path.canonicalize(path.join(scriptDir, '..', '..', '..', 'torrents'));
void main() async {
  readAndSave(path.join(torrentsPath, 'big-buck-bunny.torrent'),
      path.join(scriptDir, '..', 'tmp', 'big-buck-bunny.torrent'));
  readAndSave(path.join(torrentsPath, 'sintel.torrent'),
      path.join(scriptDir, '..', 'tmp', 'sintel.torrent'));
}

void readAndSave(String path, String newPath) async {
  var result = await Torrent.parse(path);
  printModelInfo(result);
  var newFile = await result.saveAs(newPath, true);
  var result2 = await Torrent.parse(newFile.path);
  printModelInfo(result2);
}

void printModelInfo(Torrent model) {
  print('${model.filePath} Info Hash : ${model.infoHash}');
  print('${model.filePath} announces :');
  for (var announce in model.announces) {
    print('$announce');
  }
  print('DHT nodes:');
  for (var element in model.nodes) {
    print(element);
  }

  print('${model.filePath} files :');
  for (var file in model.files) {
    print('$file');
  }
}
