import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart' as bencoding;

import 'isolate_runner.dart';
import 'torrent_file.dart';
import 'torrent_parser.dart';
import 'torrent_serializer.dart';

///
/// Torrent File Structure Model.
///
/// See [Torrent file structure](https://wiki.theory.org/BitTorrentSpecification#Metainfo_File_Structure)
///
/// See [JS Parse Torrent](https://github.com/webtorrent/parse-torrent)
class Torrent {
  ///
  /// This is prepared to be able to regenerate the torrent file because the parsed "info" will be partially ignored during the model generation process.
  /// If we directly use the model to generate the torrent file, the original "info" information will be inconsistent, and when parsing again, we won't be able to obtain
  /// the correct SHA1 information.
  ///
  dynamic get info => _info;

  /// If this model was parsed from file system, record the file path
  String? filePath;

  final dynamic _info;

  final Set<Uri> _announces = {};

  /// The announce URL list of the trackers
  Set<Uri> get announces => _announces;

  /// creation date
  DateTime? creationDate;

  /// free-form textual comments of the author
  String? comment;

  /// name and version of the program used to create the torrent file
  String? createdBy;

  /// the string encoding format used to generate the pieces part of the info dictionary in the torrent file metafile
  String? encoding;

  /// Total file bytes size;
  int length;

  /// Torrent model name.
  final String name;

  final Set<Uri> _urlList = {};

  Set<Uri> get urlList => _urlList;

  final List<TorrentFile> _files = [];

  /// The files list
  List<TorrentFile> get files => _files;

  final String infoHash;

  Uint8List infoHashBuffer;

  late int pieceLength;

  late int lastPieceLength;

  bool? private;

  /// DHT nodes
  List<Uri> nodes = [];

  final List<String> _pieces = [];

  List<String> get pieces => _pieces;

  Torrent(
      this._info, this.name, this.infoHash, this.infoHashBuffer, this.length,
      {this.createdBy, this.creationDate, this.filePath});

  void addPiece(String piece) {
    pieces.add(piece);
  }

  void removePiece(String piece) {
    pieces.remove(piece);
  }

  bool addAnnounce(Uri announce) {
    return _announces.add(announce);
  }

  bool removeAnnounce(Uri announce) {
    return _announces.remove(announce);
  }

  bool addURL(Uri url) {
    return _urlList.add(url);
  }

  bool removeURL(Uri url) {
    return _urlList.remove(url);
  }

  void addFile(TorrentFile file) {
    _files.add(file);
  }

  void removeFile(TorrentFile file) {
    _files.remove(file);
  }

  @override
  String toString() {
    return 'Torrent Model{name:$name,InfoHash:$infoHash}';
  }

  ///
  /// Parse torrent file from a file path.
  ///
  /// [filePath] is the path to the .torrent file.
  ///
  static Future<Torrent> parseFromFile(String filePath) async {
    final result = await IsolateRunner.run<Torrent>(_processIsolate, filePath);
    result.filePath = filePath;
    return result;
  }

  ///
  /// Parse torrent file from bytes.
  ///
  /// [bytes] is the bencoded content of the .torrent file.
  ///
  static Future<Torrent> parseFromBytes(Uint8List bytes) async {
    return IsolateRunner.run<Torrent>(_processIsolate, bytes);
  }

  ///
  /// Parse torrent file.
  ///
  /// The parameter can be file path(```String```) or file content bytes (```Uint8List```).
  ///
  /// This method is kept for backward compatibility. Consider using [parseFromFile] or [parseFromBytes] for type safety.
  ///
  @Deprecated('Use parseFromFile or parseFromBytes for type safety')
  static Future<Torrent> parse(dynamic data) async {
    if (data is String) {
      return parseFromFile(data);
    } else if (data is Uint8List) {
      return parseFromBytes(data);
    } else {
      throw ArgumentError(
          'Invalid argument type. Expected String (file path) or Uint8List (bytes), got ${data.runtimeType}');
    }
  }

  /// Generate .torrent bencode bytes buffer from Torrent model
  Future<Uint8List> toByteBuffer() {
    return IsolateRunner.run<Uint8List>(_processModel2BufferIsolate, this);
  }

  /// Save Torrent model to .torrent file
  ///
  /// If param [force] is true, the exist .torrent file will be re-write with
  /// the new content
  Future<File> saveAs(String? path, [bool force = false]) async {
    if (path == null) {
      throw Exception('File path is Null');
    }
    final file = File(path);
    final exists = await file.exists();
    if (exists) {
      if (!force) {
        throw Exception('file is exists');
      }
    } else {
      await file.create(recursive: true);
    }
    final content = await toByteBuffer();
    return file.writeAsBytes(content);
  }

  /// Save current model to the current file
  Future<File> save() {
    return saveAs(filePath, true);
  }
}

/// Isolate entry point for parsing torrent files.
void _processIsolate(Map<String, dynamic> data) async {
  final sender = data['sender'] as SendPort;
  final path = data['data'];
  Uint8List? bytes;

  if (path is String) {
    bytes = await File(path).readAsBytes();
  } else if (path is Uint8List) {
    bytes = path;
  }

  if (bytes == null || bytes.isEmpty) {
    throw ArgumentError('file path/contents is empty');
  }

  final torrent = bencoding.decode(bytes);
  if (torrent == null) {
    throw ArgumentError('Failed to decode torrent file');
  }

  final result = TorrentParser.parse(torrent as Map<String, dynamic>);
  sender.send(result);
}

/// Isolate entry point for serializing torrent models.
void _processModel2BufferIsolate(Map<String, dynamic> data) {
  final sender = data['sender'] as SendPort;
  final model = data['data'];

  if (model is! Torrent) {
    throw ArgumentError('The input data isn\'t Torrent model');
  }

  final result = TorrentSerializer.toByteBuffer(model);
  sender.send(result);
}
