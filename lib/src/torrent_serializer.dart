import 'dart:convert';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart' as bencoding;

import 'torrent.dart';

/// Serializes a [Torrent] model into bencoded byte buffer.
class TorrentSerializer {
  /// Converts a [Torrent] model to bencoded byte buffer.
  static Uint8List toByteBuffer(Torrent torrentModel) {
    final torrent = <String, dynamic>{'info': torrentModel.info};

    _serializeAnnounces(torrent, torrentModel);
    _serializeUrlList(torrent, torrentModel);
    _serializeOptionalFields(torrent, torrentModel);

    return bencoding.encode(torrent);
  }

  static void _serializeAnnounces(Map<String, dynamic> torrent, Torrent model) {
    final announces = model.announces;
    if (announces.isNotEmpty) {
      if (announces.length == 1) {
        torrent['announce'] = utf8.encode(announces.elementAt(0).toString());
      } else {
        torrent['announce-list'] = [];
        for (var url in announces) {
          torrent['announce-list'].add([utf8.encode(url.toString())]);
        }
      }
    }
  }

  static void _serializeUrlList(Map<String, dynamic> torrent, Torrent model) {
    if (model.urlList.isNotEmpty) {
      torrent['url-list'] = [];
      for (var url in model.urlList) {
        torrent['url-list'].add(url.toString());
      }
    }
  }

  static void _serializeOptionalFields(
      Map<String, dynamic> torrent, Torrent model) {
    if (model.private != null) {
      torrent['private'] = model.private! ? 1 : 0;
    }

    if (model.creationDate != null) {
      torrent['creation date'] =
          model.creationDate!.millisecondsSinceEpoch ~/ 1000;
    }

    if (model.createdBy != null) {
      torrent['created by'] = model.createdBy;
    }

    if (model.comment != null) {
      torrent['comment'] = model.comment;
    }
  }
}
