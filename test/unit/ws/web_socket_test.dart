// Copyright 2015 Workiva Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@TestOn('vm || browser')
import 'dart:async';

import 'package:test/test.dart';
import 'package:w_transport/mock.dart';
import 'package:w_transport/w_transport.dart' as transport;

import '../../naming.dart';
import '../../utils.dart' show nextTick;

void main() {
  final naming = new Naming()
    ..testType = testTypeUnit
    ..topic = topicWebSocket;

  group(naming.toString(), () {
    group('WSocket', () {
      // ignore: deprecated_member_use
      _runWebSocketSuite((Uri uri) => transport.WSocket.connect(uri));
      // ignore: deprecated_member_use
      _runLegacyWebSocketSuite((Uri uri) => transport.WSocket.connect(uri));
    });

    group('WebSocket', () {
      _runWebSocketSuite((Uri uri) => transport.WebSocket.connect(uri));
      _runLegacyWebSocketSuite((Uri uri) => transport.WebSocket.connect(uri));
    });
  });
}

// ignore: deprecated_member_use
void _runWebSocketSuite(Future<transport.WSocket> getWebSocket(Uri uri)) {
  MockWebSocketServer mockServer;
  final webSocketUri = Uri.parse('ws://mock.com/ws');

  setUp(() async {
    configureWTransportForTest();
    await MockTransports.reset();
    mockServer = new MockWebSocketServer();
  });

  tearDown(() async {
    await mockServer.shutDown();
  });

  test('message events should be discarded prior to a subscription', () async {
    MockTransports.webSocket.expect(webSocketUri, connectTo: mockServer);
    final webSocket = await getWebSocket(webSocketUri);
    final connection = await mockServer.onClientConnected.first;

    connection.send('1');
    connection.send('2');
    await nextTick();

    final messages = <String>[];
    webSocket.listen((data) {
      messages.add(data);
    });

    connection.send('3');
    connection.send('4');
    await nextTick();

    await connection.close();
    await webSocket.done;
    expect(messages, orderedEquals(['3', '4']));
    await webSocket.close().catchError((_) {});
  });

  test(
      'the first event should be received if a subscription is made immediately',
      () async {
    MockTransports.webSocket.expect(webSocketUri, connectTo: mockServer);
    final webSocket = await getWebSocket(webSocketUri);
    final connection = await mockServer.onClientConnected.first;

    final c = new Completer<String>();
    webSocket.listen((data) {
      c.complete(data);
    });

    connection.send('first');
    expect(await c.future, equals('first'));
    await webSocket.close().catchError((_) {});
  });

  test('all event streams should respect pause() and resume() signals',
      () async {
    MockTransports.webSocket.expect(webSocketUri, connectTo: mockServer);
    final webSocket = await getWebSocket(webSocketUri);
    final connection = await mockServer.onClientConnected.first;
    final messages = <String>[];

    // no subscription yet, messages should be discarded
    connection.send('1');
    await nextTick();

    // setup a subscription, messages should be recorded
    final sub = webSocket.listen((data) {
      messages.add(data);
    });
    connection.send('2');
    await nextTick();

    // pause the subscription, messages should be discarded
    sub.pause();
    connection.send('3');
    await nextTick();

    // resume the subscription, messages should be recorded again
    sub.resume();
    connection.send('4');
    await nextTick();

    expect(messages, orderedEquals(['2', '4']));
    await webSocket.close().catchError((_) {});
    await sub.cancel();
  });

  test('onData() handler should be reassignable', () async {
    MockTransports.webSocket.expect(webSocketUri, connectTo: mockServer);
    final webSocket = await getWebSocket(webSocketUri);
    final connection = await mockServer.onClientConnected.first;

    final origHandlerMessages = <String>[];
    final newHandlerMessages = <String>[];

    // Messages from original handler should be recorded
    final sub = webSocket.listen((data) {
      origHandlerMessages.add(data);
    });
    connection.send('orig');
    await nextTick();

    // New handler should completely replace original handler
    sub.onData((data) {
      newHandlerMessages.add(data);
    });
    connection.send('new');
    await nextTick();

    expect(origHandlerMessages, equals(['orig']));
    expect(newHandlerMessages, equals(['new']));
    await webSocket.close().catchError((_) {});
    await sub.cancel();
  });

  test('onDone() handler should be reassignable', () async {
    MockTransports.webSocket.expect(webSocketUri, connectTo: mockServer);
    final webSocket = await getWebSocket(webSocketUri);
    final connection = await mockServer.onClientConnected.first;

    final sub = webSocket.listen((_) {}, onDone: () {});

    final c = new Completer<Null>();
    sub.onDone(() {
      c.complete();
    });

    await connection.close();
    await c.future;
    await webSocket.close().catchError((_) {});
    await sub.cancel();
  });

  test('add() should send data to underlying web socket', () async {
    MockTransports.webSocket.expect(webSocketUri, connectTo: mockServer);
    final webSocket = await getWebSocket(webSocketUri);
    final connection = await mockServer.onClientConnected.first;

    final c = new Completer<String>();
    connection.onData((data) {
      if (!c.isCompleted) {
        c.complete(data);
      }
    });

    webSocket.add('message');

    expect(await c.future, equals('message'));
    await webSocket.close();
  });

  test('addStream() should send data to underlying web socket', () async {
    MockTransports.webSocket.expect(webSocketUri, connectTo: mockServer);
    final webSocket = await getWebSocket(webSocketUri);
    final connection = await mockServer.onClientConnected.first;

    final controller = new StreamController<dynamic>();
    connection.onData(controller.add);

    await webSocket.addStream(new Stream.fromIterable(['one', 'two']));
    // ignore: unawaited_futures
    controller.close();
    // ignore: unawaited_futures
    webSocket.close();

    expect(await controller.stream.toList(), equals(['one', 'two']));
  });

  test('addStream() should cause the web socket to close when erorr is added',
      () async {
    MockTransports.webSocket.expect(webSocketUri, connectTo: mockServer);
    final webSocket = await getWebSocket(webSocketUri);

    final controller = new StreamController<dynamic>();
    controller.add('message');
    controller.addError(new Exception('addStream error, should close socket'));
    // ignore: unawaited_futures
    controller.close();

    await webSocket.addStream(controller.stream);
    expect(webSocket.done, throwsException);
    await webSocket.close().catchError((_) {});
  });

  test('addError() should cause the web socket to close', () async {
    MockTransports.webSocket.expect(webSocketUri, connectTo: mockServer);
    final webSocket = await getWebSocket(webSocketUri);

    expect(webSocket.done, throwsException);
    webSocket.addError(new Exception('web socket consumer error'));
    await new Future(() {});
    await webSocket.close().catchError((_) {});
  });

  test('server closing the connection should close the socket', () async {
    MockTransports.webSocket.expect(webSocketUri, connectTo: mockServer);
    final webSocket = await getWebSocket(webSocketUri);
    final connection = await mockServer.onClientConnected.first;

    await connection.close(1000, 'closed');
    await webSocket.done;
    expect(webSocket.closeCode, equals(1000));
    expect(webSocket.closeReason, equals('closed'));
    await webSocket.close().catchError((_) {});
  });
}

// ignore: deprecated_member_use
void _runLegacyWebSocketSuite(Future<transport.WSocket> getWebSocket(Uri uri)) {
  group('legacy', () {
    final webSocketUri = Uri.parse('ws://mock.com/ws');

    setUp(() async {
      configureWTransportForTest();
      await MockTransports.reset();
    });

    test('message events should be discarded prior to a subscription',
        () async {
      // ignore: deprecated_member_use
      final mockWebSocket = new MockWSocket();
      MockTransports.webSocket.expect(webSocketUri, connectTo: mockWebSocket);
      final webSocket = await getWebSocket(webSocketUri);

      // ignore: deprecated_member_use
      mockWebSocket.addIncoming('1');
      // ignore: deprecated_member_use
      mockWebSocket.addIncoming('2');
      await nextTick();

      final messages = <String>[];
      webSocket.listen((data) {
        messages.add(data);
      });

      // ignore: deprecated_member_use
      mockWebSocket.addIncoming('3');
      // ignore: deprecated_member_use
      mockWebSocket.addIncoming('4');
      await nextTick();

      // ignore: deprecated_member_use
      mockWebSocket.triggerServerClose();
      await webSocket.done;
      expect(messages, orderedEquals(['3', '4']));
      await webSocket.close().catchError((_) {});
      await mockWebSocket.close().catchError((_) {});
    });

    test(
        'the first event should be received if a subscription is made immediately',
        () async {
      // ignore: deprecated_member_use
      final mockWebSocket = new MockWSocket();
      MockTransports.webSocket.expect(webSocketUri, connectTo: mockWebSocket);
      final webSocket = await getWebSocket(webSocketUri);

      final c = new Completer<String>();
      webSocket.listen((data) {
        c.complete(data);
      });
      // ignore: deprecated_member_use
      mockWebSocket.addIncoming('first');

      expect(await c.future, equals('first'));
      await webSocket.close().catchError((_) {});
      await mockWebSocket.close().catchError((_) {});
    });

    test('all event streams should respect pause() and resume() signals',
        () async {
      // ignore: deprecated_member_use
      final mockWebSocket = new MockWSocket();
      MockTransports.webSocket.expect(webSocketUri, connectTo: mockWebSocket);
      final webSocket = await getWebSocket(webSocketUri);
      final messages = <String>[];

      // no subscription yet, messages should be discarded
      // ignore: deprecated_member_use
      mockWebSocket.addIncoming('1');
      await nextTick();

      // setup a subscription, messages should be recorded
      final sub = webSocket.listen((data) {
        messages.add(data);
      });
      // ignore: deprecated_member_use
      mockWebSocket.addIncoming('2');
      await nextTick();

      // pause the subscription, messages should be discarded
      sub.pause();
      // ignore: deprecated_member_use
      mockWebSocket.addIncoming('3');
      await nextTick();

      // resume the subscription, messages should be recorded again
      sub.resume();
      // ignore: deprecated_member_use
      mockWebSocket.addIncoming('4');
      await nextTick();

      expect(messages, orderedEquals(['2', '4']));
      await webSocket.close().catchError((_) {});
      await mockWebSocket.close().catchError((_) {});
      await sub.cancel();
    });

    test('onData() handler should be reassignable', () async {
      // ignore: deprecated_member_use
      final mockWebSocket = new MockWSocket();
      MockTransports.webSocket.expect(webSocketUri, connectTo: mockWebSocket);
      final webSocket = await getWebSocket(webSocketUri);

      final origHandlerMessages = <String>[];
      final newHandlerMessages = <String>[];

      // Messages from original handler should be recorded
      final sub = webSocket.listen((data) {
        origHandlerMessages.add(data);
      });
      // ignore: deprecated_member_use
      mockWebSocket.addIncoming('orig');
      await nextTick();

      // New handler should completely replace original handler
      sub.onData((data) {
        newHandlerMessages.add(data);
      });
      // ignore: deprecated_member_use
      mockWebSocket.addIncoming('new');
      await nextTick();

      expect(origHandlerMessages, equals(['orig']));
      expect(newHandlerMessages, equals(['new']));
      await webSocket.close().catchError((_) {});
      await mockWebSocket.close().catchError((_) {});
      await sub.cancel();
    });

    test('onDone() handler should be reassignable', () async {
      // ignore: deprecated_member_use
      final mockWebSocket = new MockWSocket();
      MockTransports.webSocket.expect(webSocketUri, connectTo: mockWebSocket);
      final webSocket = await getWebSocket(webSocketUri);

      final sub = webSocket.listen((_) {}, onDone: () {});

      final c = new Completer<Null>();
      sub.onDone(() {
        c.complete();
      });

      // ignore: deprecated_member_use
      mockWebSocket.triggerServerClose();
      await c.future;
      await sub.cancel();
      await mockWebSocket.close();
      await webSocket.close();
    });

    test('add() should send data to underlying web socket', () async {
      // ignore: deprecated_member_use
      final mockWebSocket = new MockWSocket();
      MockTransports.webSocket.expect(webSocketUri, connectTo: mockWebSocket);
      final webSocket = await getWebSocket(webSocketUri);

      final c = new Completer<String>();
      // ignore: deprecated_member_use
      mockWebSocket.onOutgoing(c.complete);

      webSocket.add('message');

      expect(await c.future, equals('message'));
      await webSocket.close();
      await mockWebSocket.close();
    });

    test('addStream() should send data to underlying web socket', () async {
      // ignore: deprecated_member_use
      final mockWebSocket = new MockWSocket();
      MockTransports.webSocket.expect(webSocketUri, connectTo: mockWebSocket);
      final webSocket = await getWebSocket(webSocketUri);

      final controller = new StreamController<dynamic>();
      // ignore: deprecated_member_use
      mockWebSocket.onOutgoing(controller.add);

      await webSocket.addStream(new Stream.fromIterable(['one', 'two']));
      // ignore: unawaited_futures
      controller.close();
      // ignore: unawaited_futures
      webSocket.close();

      expect(await controller.stream.toList(), equals(['one', 'two']));
      await mockWebSocket.close().catchError((_) {});
    });

    test('addStream() should cause the web socket to close when erorr is added',
        () async {
      // ignore: deprecated_member_use
      final mockWebSocket = new MockWSocket();
      MockTransports.webSocket.expect(webSocketUri, connectTo: mockWebSocket);
      final webSocket = await getWebSocket(webSocketUri);

      final controller = new StreamController<dynamic>();
      controller.add('message');
      controller
          .addError(new Exception('addStream error, should close socket'));
      // ignore: unawaited_futures
      controller.close();

      await webSocket.addStream(controller.stream);

      expect(webSocket.done, throwsException);
      await new Future(() {});
      await webSocket.close().catchError((_) {});
      await mockWebSocket.close().catchError((_) {});
    });

    test('addError() should cause the web socket to close', () async {
      // ignore: deprecated_member_use
      final mockWebSocket = new MockWSocket();
      MockTransports.webSocket.expect(webSocketUri, connectTo: mockWebSocket);
      final webSocket = await getWebSocket(webSocketUri);

      expect(webSocket.done, throwsException);
      webSocket.addError(new Exception('web socket consumer error'));
      await new Future(() {});
      await mockWebSocket.close().catchError((_) {});
      await webSocket.close().catchError((_) {});
    });

    // TODO: remove this test once triggerServerError has been removed
    test('DEPRECATED: error should close the socket', () async {
      // ignore: deprecated_member_use
      final mockWebSocket = new MockWSocket();
      MockTransports.webSocket.expect(webSocketUri, connectTo: mockWebSocket);
      final webSocket = await getWebSocket(webSocketUri);

      // ignore: deprecated_member_use
      mockWebSocket.triggerServerError(new Exception('Server Exception'));
      await webSocket.done;

      await mockWebSocket.close().catchError((_) {});
      await webSocket.close().catchError((_) {});
    });

    test('server closing the connection should close the socket', () async {
      // ignore: deprecated_member_use
      final mockWebSocket = new MockWSocket();
      MockTransports.webSocket.expect(webSocketUri, connectTo: mockWebSocket);
      final webSocket = await getWebSocket(webSocketUri);
      // ignore: deprecated_member_use
      mockWebSocket.triggerServerClose(1000, 'closed');
      await webSocket.done;
      expect(webSocket.closeCode, equals(1000));
      expect(webSocket.closeReason, equals('closed'));

      await mockWebSocket.close();
      await webSocket.close();
    });
  });
}
