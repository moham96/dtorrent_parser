#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';
import 'package:dtorrent_parser/dtorrent_parser.dart';

void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('Usage: dtorrent_parse <path_to_torrent_file>');
    exit(1);
  }
  final filePath = arguments[0];
  final file = File(filePath);
  if (!await file.exists()) {
    stderr.writeln('File not found: $filePath');
    exit(2);
  }

  try {
    final torrent = await Torrent.parse(filePath);
    final info = <String, dynamic>{
      'name': torrent.name,
      'announce': torrent.announces.map((u) => u.toString()).toList(),
      'infoHash': torrent.infoHash,
      'created': torrent.creationDate?.toUtc().toIso8601String() ?? '',
      'createdBy': torrent.createdBy ?? '',
      'comment': torrent.comment ?? '',
      'urlList': torrent.urlList.map((u) => u.toString()).toList(),
      'files': torrent.files
          .map((f) => {
                'path': f.path,
                'name': f.name,
                'length': f.length,
                'offset': f.offset,
              })
          .toList(),
      'length': torrent.length,
      'pieceLength': torrent.pieceLength,
      'lastPieceLength': torrent.lastPieceLength,
      'pieces': torrent.pieces.map((p) => p.toString()).toList(),
    };
    print(JsonEncoder.withIndent('  ').convert(info));
  } catch (e) {
    stderr.writeln('Failed to parse torrent: $e');
    exit(3);
  }
}
