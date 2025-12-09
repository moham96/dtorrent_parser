A Dart library for parsing .torrent file to Torrent model/saving Torrent model to .torrent file.

[![codecov](https://codecov.io/gh/moham96/dtorrent_parser/branch/main/graph/badge.svg)](https://codecov.io/gh/moham96/dtorrent_parser)

## Support 
- [BEP 0005 DHT Protocol](https://www.bittorrent.org/beps/bep_0005.html)
- [BEP 0012 Multitracker Metadata Extension](https://www.bittorrent.org/beps/bep_0012.html)
- [BEP 0019 WebSeed - HTTP/FTP Seeding (GetRight style)](https://www.bittorrent.org/beps/bep_0019.html)

## Usage

A simple usage example:

### Parse .torrent file

```dart
import 'package:dtorrent_parser/dtorrent_parser.dart';

main() {
  ....

  var model = Torrent.parse('some.torrent');

  ....
}
```

Use ```Torrent``` class' static method ```parse``` to get a torrent model. The important informations of .torrent file can be found in the torrent model , such as ```announces``` list , ```infoHash``` ,etc..

## Testing

Run tests:
```bash
dart test
```

Run tests with coverage:
```bash
dart test --coverage=coverage
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --packages=.dart_tool/package_config.json --report-on=lib
```

Or use the provided script:
```bash
dart tool/coverage.dart
```

The coverage report will be generated at `coverage/lcov.info` and can be viewed with tools like `genhtml` or uploaded to services like Codecov.

Coverage is automatically uploaded to [Codecov](https://codecov.io) on every push and pull request via GitHub Actions.

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/moham96/dtorrent_parser/issues
