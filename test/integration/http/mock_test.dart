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
library w_transport.test.integration.http.mock_test;

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:w_transport/w_transport.dart';
import 'package:w_transport/w_transport_mock.dart';

import 'common.dart';

void main() {
  configureWTransportForTest();

  HttpIntegrationConfig config =
      new HttpIntegrationConfig('Mock', Uri.parse('http://mocks.com'));

  MockTransports.http.when(config.downloadEndpointUri, (_) async {
    var byteStream = new Stream.fromIterable([UTF8.encode('file')]);
    return new MockStreamedResponse.ok(byteStream: byteStream);
  });

  MockTransports.http.when(config.fourOhFourEndpointUri,
      (_) async => new MockResponse.notFound());

  MockTransports.http.when(config.reflectEndpointUri, (FinalizedRequest request) async {
    String body;
    if (request.body is StreamedHttpBody) {
      body = await request.body.decode();
    } else {
      body = (request.body as HttpBody).asString();
    }
    Map reflection = {
      'method': request.method,
      'path': request.uri.path,
      'headers': request.headers,
      'body': body,
    };
    return new MockResponse.ok(body: JSON.encode(reflection));
  });

  MockTransports.http.when(config.timeoutEndpointUri, (_) async {
    return new Completer().future;
  });

  group(config.title, () {
    tearDown(() {
      MockTransports.verifyNoOutstandingExceptions();
    });

    runCommonHttpIntegrationTests(config);
  });
}
