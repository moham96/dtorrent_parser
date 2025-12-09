/// Validates torrent file structure according to BitTorrent specification.
class TorrentValidator {
  /// Validates that a torrent map contains all required fields.
  ///
  /// Throws [TorrentValidationException] if validation fails.
  static void validate(Map<String, dynamic> torrent) {
    _validateInfo(torrent);
    _validateName(torrent);
    _validatePieceLength(torrent);
    _validatePieces(torrent);
    _validateFiles(torrent);
  }

  static void _validateInfo(Map<String, dynamic> torrent) {
    if (torrent['info'] == null) {
      throw TorrentValidationException(
          'Torrent is missing required field: info');
    }
  }

  static void _validateName(Map<String, dynamic> torrent) {
    final info = torrent['info'] as Map<String, dynamic>;
    if (info['name.utf-8'] == null && info['name'] == null) {
      throw TorrentValidationException(
          'Torrent is missing required field: info.name');
    }
  }

  static void _validatePieceLength(Map<String, dynamic> torrent) {
    final info = torrent['info'] as Map<String, dynamic>;
    if (info['piece length'] == null) {
      throw TorrentValidationException(
          'Torrent is missing required field: info[\'piece length\']');
    }
  }

  static void _validatePieces(Map<String, dynamic> torrent) {
    final info = torrent['info'] as Map<String, dynamic>;
    if (info['pieces'] == null) {
      throw TorrentValidationException(
          'Torrent is missing required field: info.pieces');
    }
  }

  static void _validateFiles(Map<String, dynamic> torrent) {
    final info = torrent['info'] as Map<String, dynamic>;
    final files = info['files'];
    if (files != null) {
      if (files is List) {
        for (var i = 0; i < files.length; i++) {
          final file = files[i] as Map<String, dynamic>;
          if (file['path.utf-8'] == null && file['path'] == null) {
            throw TorrentValidationException(
                'Torrent is missing required field: info.files[$i].path');
          }
        }
      }
    } else {
      if (info['length'] == null || info['length'] is! num) {
        throw TorrentValidationException(
            'Torrent is missing required field: info.length');
      }
    }
  }
}

/// Exception thrown when torrent validation fails.
class TorrentValidationException implements Exception {
  final String message;
  TorrentValidationException(this.message);

  @override
  String toString() => message;
}
