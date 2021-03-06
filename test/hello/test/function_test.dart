// Copyright 2021 Google LLC
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

@Timeout(Duration(seconds: 3))
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:io/io.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

const defaultPort = '8080';

void main() {
  group('http function tests', () {
    test('defaults', () async {
      final proc = await _start();

      final response = await get('http://localhost:$defaultPort');
      expect(response.statusCode, 200);
      expect(response.body, 'Hello, World!');

      await _finish(proc);
    });

    test('SIGINT also terminates the server', () async {
      final proc = await _start();

      final response = await get('http://localhost:$defaultPort');
      expect(response.statusCode, 200);
      expect(response.body, 'Hello, World!');

      await _finish(proc, signal: ProcessSignal.sigint);
    });

    test('good options', () async {
      const port = '9000';
      final proc = await _start(
        port: port,
        arguments: [
          '--port',
          port,
          '--target',
          'function',
          '--signature-type',
          'http'
        ],
        env: {
          // make sure args have precedence over environment
          'FUNCTION_TARGET': 'foo', // overridden by --target
          'FUNCTION_SIGNATURE_TYPE':
              'cloudevent', // overridden by --signature-type
        },
      );

      final response = await get('http://localhost:$port');
      expect(response.statusCode, 200);
      expect(response.body, 'Hello, World!');

      await _finish(proc);
    });

    group('environment', () {
      test('good environment', () async {
        const port = '8888';
        final proc = await _start(port: port, env: {
          'PORT': port,
        });

        final response = await get('http://localhost:$port');
        expect(response.statusCode, 200);
        expect(response.body, 'Hello, World!');

        await _finish(proc);
      });

      test('bad FUNCTION_TARGET', () async {
        final proc = await _start(shouldFail: true, env: {
          'FUNCTION_TARGET': 'bob',
        });

        await expectLater(
          proc.stderr,
          emitsThrough(
            'There is no handler configured for FUNCTION_TARGET `bob`.',
          ),
        );

        await proc.shouldExit(ExitCode.usage.code);
      });

      test('bad FUNCTION_SIGNATURE_TYPE', () async {
        final proc = await _start(shouldFail: true, env: {
          'FUNCTION_SIGNATURE_TYPE': 'bob',
        });

        await expectLater(
          proc.stderr,
          emitsThrough(
            'FUNCTION_SIGNATURE_TYPE environment variable "bob" is not a valid '
            'option (must be "http" or "cloudevent")',
          ),
        );

        await proc.shouldExit(ExitCode.usage.code);
      });

      test('bad PORT', () async {
        final proc = await _start(shouldFail: true, env: {
          'PORT': 'bob',
        });

        await expectLater(
          proc.stderr,
          emitsThrough(
            'Bad value for environment variable "PORT" – "bob" – '
            'Invalid radix-10 number.',
          ),
        );

        await proc.shouldExit(ExitCode.usage.code);
      });
    });

    group('command line', () {
      test('unsupported option', () async {
        final proc = await _start(
          shouldFail: true,
          arguments: [
            '--bob',
          ],
        );

        await expectLater(
          proc.stderr,
          emitsInOrder([
            'Could not find an option named "bob".',
            ...LineSplitter.split(_usage),
          ]),
        );

        await proc.shouldExit(ExitCode.usage.code);
      });

      test('bad target', () async {
        final proc = await _start(
          shouldFail: true,
          arguments: [
            '--target',
            'bob',
          ],
        );

        await expectLater(
          proc.stderr,
          emitsThrough(
            'There is no handler configured for FUNCTION_TARGET `bob`.',
          ),
        );

        await proc.shouldExit(ExitCode.usage.code);
      });

      test('bad signature', () async {
        final proc = await _start(
          shouldFail: true,
          arguments: ['--signature-type', 'foo'],
        );

        await expectLater(
          proc.stderr,
          emitsInOrder([
            '"foo" is not an allowed value for option "signature-type".',
            ...LineSplitter.split(_usage),
          ]),
        );

        await proc.shouldExit(ExitCode.usage.code);
      });

      test('bad port', () async {
        final proc = await _start(
          shouldFail: true,
          arguments: ['--port', 'foo'],
        );

        await expectLater(
          proc.stderr,
          emitsInOrder([
            'Bad value for "port" – "foo" – Invalid radix-10 number.',
            ...LineSplitter.split(_usage),
          ]),
        );

        await proc.shouldExit(ExitCode.usage.code);
      });
    });
  });

  group('not found assets', () {
    for (var item in const {'robots.txt', 'favicon.ico'}) {
      test('404 for $item', () async {
        final proc = await _start();

        final response = await get('http://localhost:$defaultPort/$item');
        expect(response.statusCode, 404);
        expect(response.body, 'Not found.');

        await _finish(proc, requestOutput: endsWith('GET     [404] /$item'));
      });
    }
  });

  group('cloudevent function tests', () {});
}

Future<TestProcess> _start({
  bool shouldFail = false,
  String port = defaultPort,
  Map<String, String> env,
  Iterable<String> arguments = const <String>[],
}) async {
  final args = [
    'bin/main.dart',
    ...arguments,
  ];
  final proc = await TestProcess.start('dart', args, environment: env);

  if (!shouldFail) {
    await expectLater(
      proc.stdout,
      emitsThrough('App listening on :$port'),
    );
  }

  return proc;
}

Future<void> _finish(
  TestProcess proc, {
  ProcessSignal signal = ProcessSignal.sigterm,
  Object requestOutput,
}) async {
  requestOutput ??= endsWith('GET     [200] /');
  await expectLater(
    proc.stdout,
    emitsThrough(requestOutput),
  );
  proc.signal(signal);
  await proc.shouldExit(0);
  await expectLater(
    proc.stdout,
    emitsThrough('Got signal $signal - closing'),
  );
}

const _usage = r'''
--port              The port on which the Functions Framework listens for
                    requests.
                    Overrides the PORT environment variable.
--target            The name of the exported function to be invoked in response
                    to requests.
                    Overrides the FUNCTION_TARGET environment variable.
--signature-type    The signature used when writing your function. Controls
                    unmarshalling rules and determines which arguments are used
                    to invoke your function.
                    Overrides the FUNCTION_SIGNATURE_TYPE environment variable.
                    [http, cloudEvent]''';
