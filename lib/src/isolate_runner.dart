import 'dart:async';
import 'dart:isolate';

/// Runs computations in isolates for better performance.
class IsolateRunner {
  /// Runs a computation in an isolate.
  ///
  /// [mainMethod] is the entry point function for the isolate.
  /// [data] is the data to pass to the isolate.
  ///
  /// Returns a [Future] that completes with the result from the isolate.
  static Future<T> run<T>(
      void Function(Map<String, dynamic>) mainMethod, dynamic data) {
    final completer = Completer<T>();
    final port = ReceivePort();
    final errorPort = ReceivePort();

    void cleanAll(Isolate isolate) {
      port.close();
      errorPort.close();
      isolate.kill();
    }

    Isolate.spawn(mainMethod, {'sender': port.sendPort, 'data': data},
            onError: errorPort.sendPort)
        .then((isolate) {
      port.listen((message) {
        cleanAll(isolate);
        completer.complete(message as T);
      });

      errorPort.listen((error) {
        cleanAll(isolate);
        completer.completeError(error);
      });
    }).catchError((error) {
      port.close();
      errorPort.close();
      completer.completeError(error);
    });

    return completer.future;
  }
}
