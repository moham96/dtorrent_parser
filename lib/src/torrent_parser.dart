import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart' as bencoding;
import 'package:crypto/crypto.dart';

import 'torrent.dart';
import 'torrent_file.dart';
import 'torrent_validator.dart';

/// Parses torrent file content into a [Torrent] model.
class TorrentParser {
  /// Parses a torrent map into a [Torrent] model.
  ///
  /// Throws [TorrentValidationException] if the torrent structure is invalid.
  static Torrent parse(Map<String, dynamic> torrent) {
    TorrentValidator.validate(torrent);

    final info = torrent['info'] as Map<String, dynamic>;
    final nameRaw = info['name.utf-8'] ?? info['name'];
    final torrentName = nameRaw is Uint8List
        ? _decodeString(nameRaw)
        : (nameRaw as String? ?? '');

    final sha1Info = sha1.convert(bencoding.encode(info));
    final torrentModel = Torrent(
      info,
      torrentName,
      sha1Info.toString(),
      Uint8List.fromList(sha1Info.bytes),
      0,
    );

    _parseOptionalFields(torrent, torrentModel);
    _parseAnnounces(torrent, torrentModel);
    _parseUrlList(torrent, torrentModel);
    _parseFiles(torrent, torrentModel);
    _parsePieces(torrent, torrentModel);
    _parseNodes(torrent, torrentModel);

    return torrentModel;
  }

  static void _parseOptionalFields(
      Map<String, dynamic> torrent, Torrent torrentModel) {
    final encodingRaw = torrent['encoding'];
    if (encodingRaw != null) {
      torrentModel.encoding = encodingRaw is Uint8List
          ? _decodeString(encodingRaw)
          : (encodingRaw as String? ?? '');
    }

    final info = torrent['info'] as Map<String, dynamic>;
    if (info['private'] != null) {
      torrentModel.private = (info['private'] == 1);
    }

    if (torrent['creation date'] != null) {
      torrentModel.creationDate = DateTime.fromMillisecondsSinceEpoch(
          (torrent['creation date'] as int) * 1000);
    }

    final createdByRaw = torrent['created by'];
    if (createdByRaw != null) {
      torrentModel.createdBy = createdByRaw is Uint8List
          ? _decodeString(createdByRaw)
          : (createdByRaw as String? ?? '');
    }

    if (torrent['comment'] is Uint8List) {
      torrentModel.comment = _decodeString(torrent['comment'] as Uint8List);
    } else if (torrent['comment'] is String) {
      torrentModel.comment = torrent['comment'] as String;
    }
  }

  static void _parseAnnounces(
      Map<String, dynamic> torrent, Torrent torrentModel) {
    // BEP 0012: Multiple trackers
    final announceList = torrent['announce-list'];
    if (announceList != null && announceList is Iterable) {
      if (announceList.isNotEmpty) {
        for (var urls in announceList) {
          // Some are list of urls
          if (urls is List && urls.isNotEmpty && urls[0] is List) {
            for (var url in urls) {
              _tryAddAnnounce(torrentModel, url);
            }
          } else {
            _tryAddAnnounce(torrentModel, urls);
          }
        }
      }
    }

    // Fallback to single announce
    if (torrent['announce'] != null) {
      _tryAddAnnounce(torrentModel, torrent['announce']);
    }
  }

  static void _tryAddAnnounce(Torrent torrentModel, dynamic url) {
    try {
      final urlString = _decodeString(url as Uint8List);
      final uri = Uri.parse(urlString);
      torrentModel.addAnnounce(uri);
    } catch (e) {
      // Silently ignore invalid URLs
    }
  }

  static void _parseUrlList(
      Map<String, dynamic> torrent, Torrent torrentModel) {
    // BEP19: Web seeding
    final urlList = torrent['url-list'];
    if (urlList != null && urlList is Iterable) {
      for (var url in urlList) {
        try {
          final urlString = _decodeString(url as Uint8List);
          final uri = Uri.parse(urlString);
          torrentModel.addURL(uri);
        } catch (e) {
          // Silently ignore invalid URLs
        }
      }
    }
  }

  static void _parseFiles(Map<String, dynamic> torrent, Torrent torrentModel) {
    final info = torrent['info'] as Map<String, dynamic>;
    final files = info['files'] ?? [info];
    var totalLength = 0;

    for (var i = 0; i < files.length; i++) {
      final file = files[i] as Map<String, dynamic>;
      final filePathRaw = file['path.utf-8'] ?? file['path'];
      // For single-file torrents, filePathRaw is null, use empty list
      final filePath =
          filePathRaw != null ? (filePathRaw as List<dynamic>) : <dynamic>[];
      final pathParts = _buildPathParts(torrentModel.name, filePath);
      final filePathString = _buildFilePath(pathParts);
      // For single-file torrents, use the torrent name as the file name
      final fileName = pathParts.length > 1
          ? (pathParts.last ?? torrentModel.name)
          : torrentModel.name;

      final fileLength = file['length'] as int;
      final offset = totalLength;
      totalLength += fileLength;

      torrentModel
          .addFile(TorrentFile(fileName, filePathString, fileLength, offset));
    }

    torrentModel.length = totalLength;

    if (torrentModel.files.isNotEmpty) {
      final pieceLength = info['piece length'] as int;
      torrentModel.pieceLength = pieceLength;
      // Calculate lastPieceLength based on total length
      final remainder = totalLength % pieceLength;
      torrentModel.lastPieceLength = remainder == 0 ? pieceLength : remainder;
    }
  }

  static List<String?> _buildPathParts(
      String torrentName, List<dynamic> filePath) {
    final parts = [torrentName, ...filePath];
    return parts.map((e) {
      if (e is List<int>) {
        return _decodeString(Uint8List.fromList(e));
      }
      if (e is String) return e;
      return null;
    }).toList();
  }

  static String _buildFilePath(List<String?> pathParts) {
    var path = '';
    for (var i = 0; i < pathParts.length; i++) {
      final prefix = i > 0 ? Platform.pathSeparator : '';
      final part = pathParts[i] != null ? prefix + pathParts[i]! : '';
      path = "$path$part";
    }
    return path;
  }

  static void _parsePieces(Map<String, dynamic> torrent, Torrent torrentModel) {
    final info = torrent['info'] as Map<String, dynamic>;
    final pieces = info['pieces'] as Uint8List;
    final pieceHashes = _splitPieces(pieces);
    for (var piece in pieceHashes) {
      torrentModel.addPiece(piece);
    }
  }

  static List<String> _splitPieces(Uint8List buf) {
    final pieces = <String>[];
    for (var i = 0; i < buf.length; i += 20) {
      final end = (i + 20 < buf.length) ? i + 20 : buf.length;
      final array = buf.sublist(i, end);
      final str = array.fold<String>('', (previousValue, byte) {
        final hex = byte.toRadixString(16).padLeft(2, '0');
        return previousValue + hex;
      });
      pieces.add(str);
    }
    return pieces;
  }

  static void _parseNodes(Map<String, dynamic> torrent, Torrent torrentModel) {
    // BEP 0005: DHT nodes
    final nodes = torrent['nodes'];
    if (nodes != null && nodes is List) {
      for (var node in nodes) {
        if (node is List &&
            node.length >= 2 &&
            node[0] != null &&
            node[1] != null) {
          try {
            final ipstr = _decodeString(node[0] as Uint8List);
            final port = node[1] as int;
            torrentModel.nodes.add(Uri(host: ipstr, port: port));
          } catch (e) {
            // Silently ignore invalid nodes
          }
        }
      }
    }
  }

  static String _decodeString(Uint8List list) {
    try {
      return utf8.decode(list);
    } catch (e) {
      return String.fromCharCodes(list);
    }
  }
}
