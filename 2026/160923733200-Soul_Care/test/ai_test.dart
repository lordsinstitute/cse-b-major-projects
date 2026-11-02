import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/ai_chat_provider.dart';
import 'package:soul_care/core/ai/ai_config.dart';
import 'package:soul_care/core/ai/ai_connection.dart';
import 'package:soul_care/core/ai/ai_domain_guard.dart';
import 'package:soul_care/core/ai/ai_models.dart';
import 'package:soul_care/core/ai/ai_prompts.dart';
import 'package:soul_care/core/ai/ai_secure_store.dart';
import 'package:soul_care/core/ai/cloud_ai_provider.dart';
import 'package:soul_care/core/ai/local_ai_provider.dart';
import 'package:soul_care/core/ai/soulcare_ai_service.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/ai_chat.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/ai_chat_repository.dart';
import 'package:soul_care/data/repositories/ai_config_repository.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/stress_repository.dart';

/// Fake OpenAI-compatible server (llama.cpp shape for local, auth-gated
/// shape for cloud OpenAI/custom).
class FakeOpenAiServer {
  final HttpServer _server;
  final List<String> modelIds;
  final List<String> tokens;
  final Duration tokenGap;
  final Duration headerDelay;
  final bool malformedModels;
  final String? requireBearer;
  int requestCount = 0;
  final List<Map<String, dynamic>> seenRequests = [];

  FakeOpenAiServer._(
    this._server, {
    required this.modelIds,
    required this.tokens,
    required this.tokenGap,
    required this.headerDelay,
    required this.malformedModels,
    required this.requireBearer,
  });

  int get port => _server.port;
  String get baseUrl => 'http://127.0.0.1:$port/v1';

  static Future<FakeOpenAiServer> start({
    List<String> modelIds = const ['gemma-4-e2b-it'],
    List<String> tokens = const ['Hello', ' SoulCare'],
    Duration tokenGap = const Duration(milliseconds: 5),
    Duration headerDelay = Duration.zero,
    bool malformedModels = false,
    String? requireBearer,
  }) async {
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeOpenAiServer._(server,
        modelIds: modelIds,
        tokens: tokens,
        tokenGap: tokenGap,
        headerDelay: headerDelay,
        malformedModels: malformedModels,
        requireBearer: requireBearer);
    server.listen(fake._handle);
    return fake;
  }

  bool _authed(HttpRequest req) {
    if (requireBearer == null) return true;
    return req.headers.value('authorization') ==
        'Bearer $requireBearer';
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      requestCount++;
      if (req.uri.path.endsWith('/models')) {
        if (!_authed(req)) {
          req.response.statusCode = 401;
          await req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType.json;
        if (malformedModels) {
          req.response.write('not-json{{{');
        } else {
          req.response.write(jsonEncode({
            'data': [
              for (final id in modelIds) {'id': id}
            ],
          }));
        }
        await req.response.close();
        return;
      }
      if (req.uri.path.endsWith('/chat/completions')) {
        if (!_authed(req)) {
          req.response.statusCode = 401;
          await req.response.close();
          return;
        }
        final body = await utf8.decoder.bind(req).join();
        try {
          seenRequests.add(
              jsonDecode(body) as Map<String, dynamic>);
        } catch (_) {}
        if (headerDelay > Duration.zero) {
          await Future<void>.delayed(headerDelay);
        }
        req.response.headers.contentType =
            ContentType('text', 'event-stream');
        for (final t in tokens) {
          req.response.write('data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': t}
                  }
                ]
              })}\n\n');
          await req.response.flush();
          await Future<void>.delayed(tokenGap);
        }
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    } catch (_) {}
  }

  Future<void> stop() => _server.close(force: true);
}

/// Fake Google AI REST surface (v1beta models + streamGenerateContent SSE).
class FakeGeminiServer {
  final HttpServer _server;
  final String validKey;
  final List<String> tokens;
  int requestCount = 0;
  final List<Map<String, dynamic>> seenRequests = [];

  FakeGeminiServer._(this._server,
      {required this.validKey, required this.tokens});

  int get port => _server.port;
  String get baseUrl =>
      'http://127.0.0.1:$port/v1beta';

  static Future<FakeGeminiServer> start({
    String validKey = 'test-gemini-key',
    List<String> tokens = const ['Hello', ' SoulCare'],
  }) async {
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeGeminiServer._(server,
        validKey: validKey, tokens: tokens);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      requestCount++;
      if (req.uri.queryParameters['key'] != validKey) {
        req.response.statusCode = 400;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'error': {'message': 'API key not valid.'}
        }));
        await req.response.close();
        return;
      }
      if (req.uri.path.endsWith('/models')) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'models': [
            {'name': 'models/gemini-2.0-flash'}
          ],
        }));
        await req.response.close();
        return;
      }
      if (req.uri.path.contains(':streamGenerateContent')) {
        final body = await utf8.decoder.bind(req).join();
        try {
          seenRequests.add(
              jsonDecode(body) as Map<String, dynamic>);
        } catch (_) {}
        req.response.headers.contentType =
            ContentType('text', 'event-stream');
        for (final t in tokens) {
          req.response.write('data: ${jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': t}
                      ]
                    }
                  }
                ]
              })}\n\n');
          await req.response.flush();
          await Future<void>.delayed(
              const Duration(milliseconds: 5));
        }
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    } catch (_) {}
  }

  Future<void> stop() => _server.close(force: true);
}

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_ai');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.experimentsBoxName),
    Hive.openBox(LocalDatabase.settingsBoxName),
    Hive.openBox(LocalDatabase.aiConversationsBoxName),
    Hive.openBox(LocalDatabase.aiMessagesBoxName),
  ]);
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

AiConfig _localConfig(String baseUrl, {AiMode mode = AiMode.local}) =>
    AiConfig(
        mode: mode,
        local: LocalAiSettings(serverUrl: baseUrl));

CloudAiProvider _cloudProvider({
  required AiConfig config,
  required CloudKeyStore keys,
}) =>
    CloudAiProvider(
      configOf: () => config,
      apiKeyOf: () =>
          AiSecureStore(store: keys).readKey(config.cloud.provider),
    );

SoulCareAiService _serviceFor({
  required LocalAiProvider local,
  required CloudAiProvider cloud,
  required AiConfig config,
  required AiConnectionManager connection,
}) =>
    SoulCareAiService(
      local: local,
      cloud: cloud,
      configOf: () => config,
      connection: connection,
    );

void main() {
  // NOTE: no TestWidgetsFlutterBinding here on purpose — flutter_test
  // replaces every HttpClient with a 400-returning mock once the binding
  // initializes, which would make real loopback HTTP untestable. Nothing
  // in this file pumps widgets; Hive and the fake servers are pure dart:io.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await _initTestHive();
  });

  tearDown(() async {
    await LocalDatabase.clearAll();
  });

  group('local provider', () {
    test('server available: connects with latency + models', () async {
      final s = await FakeOpenAiServer.start(
          modelIds: ['gemma-4-e2b-it']);
      try {
        final p = LocalAiProvider(
            configOf: () => _localConfig(s.baseUrl));
        final st = await p.testConnection();
        expect(st.ok, isTrue);
        expect(st.latencyMs, isNotNull);
        expect(st.modelCount, 1);
        expect(st.activeModelId, 'gemma-4-e2b-it');
        expect(await p.initialize(),
            AiProviderStatus.ready);
        expect(p.isLocal, isTrue);
      } finally {
        await s.stop();
      }
    });

    test('server unavailable: friendly error, never a crash',
        () async {
      final p = LocalAiProvider(
          configOf: () => const AiConfig(
              local: LocalAiSettings(
                  serverUrl: 'http://127.0.0.1:1/v1')));
      final st = await p.testConnection();
      expect(st.ok, isFalse);
      expect(st.error, isNotEmpty);
      expect(st.error, isNot(contains('Exception')));
      expect(await p.initialize(),
          AiProviderStatus.unavailable);
    });

    test('stopped server fails gracefully', () async {
      final s = await FakeOpenAiServer.start();
      final url = s.baseUrl;
      await s.stop();
      final p = LocalAiProvider(
          configOf: () => _localConfig(url));
      expect((await p.testConnection()).ok, isFalse);
    });

    test('model unavailable: empty list means no active model',
        () async {
      final s =
          await FakeOpenAiServer.start(modelIds: []);
      try {
        final p = LocalAiProvider(
            configOf: () => _localConfig(s.baseUrl));
        expect(await p.getModels(), isEmpty);
        expect(
            () => p
                .generateResponse(messages: const [
                  AiMessage(
                      role: AiRole.user, content: 'hi')
                ], options: const AiGenerationOptions(
                    temperature: 0.7,
                    maxTokens: 64,
                    topP: 0.9))
                .toList(),
            throwsA(predicate((e) =>
                e is AiProviderException &&
                e.kind == AiFailureKind.modelMissing)));
      } finally {
        await s.stop();
      }
    });

    test('malformed models response is an error, not a crash',
        () async {
      final s = await FakeOpenAiServer.start(
          malformedModels: true);
      try {
        final p = LocalAiProvider(
            configOf: () => _localConfig(s.baseUrl));
        expect((await p.testConnection()).ok, isFalse);
      } finally {
        await s.stop();
      }
    });

    test('stream delivers the full answer', () async {
      final s = await FakeOpenAiServer.start();
      try {
        final p = LocalAiProvider(
            configOf: () => _localConfig(s.baseUrl));
        final out = <String>[];
        await for (final c in p.generateResponse(
            messages: const [
              AiMessage(
                  role: AiRole.user,
                  content: 'Hello SoulCare.')
            ],
            options: const AiGenerationOptions(
                temperature: 0.7,
                maxTokens: 64,
                topP: 0.9))) {
          if (!c.done) out.add(c.text);
        }
        expect(out.join(), 'Hello SoulCare');
      } finally {
        await s.stop();
      }
    });

    test('cancellation stops the stream', () async {
      final s = await FakeOpenAiServer.start(
          tokens: List.generate(50, (i) => 't$i '),
          tokenGap: const Duration(milliseconds: 20));
      try {
        final p = LocalAiProvider(
            configOf: () => _localConfig(s.baseUrl));
        final seen = <String>[];
        var done = false;
        final sub = p
            .generateResponse(messages: const [
              AiMessage(role: AiRole.user, content: 'go')
            ], options: const AiGenerationOptions(
                temperature: 0.7, maxTokens: 512, topP: 0.9))
            .listen(
          (t) => seen.add(t.text),
          onDone: () => done = true,
        );
        final sw = Stopwatch()..start();
        while (seen.isEmpty &&
            sw.elapsed < const Duration(seconds: 10)) {
          await Future<void>.delayed(
              const Duration(milliseconds: 20));
        }
        expect(seen, isNotEmpty);
        await p.cancelGeneration();
        final sw2 = Stopwatch()..start();
        while (!done &&
            sw2.elapsed < const Duration(seconds: 10)) {
          await Future<void>.delayed(
              const Duration(milliseconds: 20));
        }
        expect(done, isTrue);
        await sub.cancel();
        expect(
            seen.where((t) => t.isNotEmpty).join().isNotEmpty,
            isTrue);
        expect(seen.length, lessThanOrEqualTo(51));
      } finally {
        await s.stop();
      }
    });

    test('overlong prompt is refused with guidance, no HTTP',
        () async {
      final s = await FakeOpenAiServer.start();
      try {
        final p = LocalAiProvider(
            configOf: () => _localConfig(s.baseUrl));
        final long = 'word ' * 20000;
        await expectLater(
            p
                .generateResponse(messages: [
                  AiMessage(
                      role: AiRole.user, content: long)
                ], options: const AiGenerationOptions(
                    temperature: 0.7,
                    maxTokens: 64,
                    topP: 0.9))
                .toList(),
            throwsA(predicate((e) =>
                e is AiProviderException &&
                e.kind == AiFailureKind.tooLong)));
        expect(s.seenRequests, isEmpty);
      } finally {
        await s.stop();
      }
    });
  });

  group('cloud provider (OpenAI-compatible)', () {
    test('valid key connects and streams', () async {
      final s = await FakeOpenAiServer.start(
          modelIds: ['gpt-4o-mini'],
          requireBearer: 'good-key');
      try {
        final keys = InMemoryCloudKeyStore();
        await keys.write(
            'soulcare_cloud_key_openAI', 'good-key');
        final config = AiConfig(
            mode: AiMode.cloud,
            cloud: CloudAiSettings(
                provider: CloudProviderKind.openAI,
                endpoint: s.baseUrl,
                model: 'gpt-4o-mini'));
        final p = _cloudProvider(
            config: config, keys: keys);
        final st = await p.testConnection();
        expect(st.ok, isTrue);
        expect(st.activeModelId, 'gpt-4o-mini');
        expect(p.isLocal, isFalse);
        expect(p.providerLabel, contains('OpenAI'));
        final text = await p
            .generateResponse(messages: const [
              AiMessage(
                  role: AiRole.user, content: 'hi')
            ], options: const AiGenerationOptions(
                temperature: 0.7, maxTokens: 64, topP: 0.9))
            .where((c) => !c.done)
            .map((c) => c.text)
            .join();
        expect(text, 'Hello SoulCare');
      } finally {
        await s.stop();
      }
    });

    test('invalid key is reported as unauthorized', () async {
      final s = await FakeOpenAiServer.start(
          requireBearer: 'good-key');
      try {
        final keys = InMemoryCloudKeyStore();
        await keys.write(
            'soulcare_cloud_key_openAI', 'bad-key');
        final config = AiConfig(
            mode: AiMode.cloud,
            cloud: CloudAiSettings(
                provider: CloudProviderKind.openAI,
                endpoint: s.baseUrl,
                model: 'gpt-4o-mini'));
        final p = _cloudProvider(
            config: config, keys: keys);
        final st = await p.testConnection();
        expect(st.ok, isFalse);
        expect(st.error, AiErrors.unauthorized);
      } finally {
        await s.stop();
      }
    });

    test('missing key never touches the network', () async {
      final s = await FakeOpenAiServer.start(
          requireBearer: 'good-key');
      try {
        final before = s.requestCount;
        final config = AiConfig(
            mode: AiMode.cloud,
            cloud: CloudAiSettings(
                provider: CloudProviderKind.openAI,
                endpoint: s.baseUrl,
                model: 'gpt-4o-mini'));
        final p = _cloudProvider(
            config: config,
            keys: InMemoryCloudKeyStore());
        final st = await p.testConnection();
        expect(st.ok, isFalse);
        expect(st.error, AiErrors.missingKey);
        expect(s.requestCount, before);
        await expectLater(
            p
                .generateResponse(messages: const [
                  AiMessage(
                      role: AiRole.user, content: 'hi')
                ], options: const AiGenerationOptions(
                    temperature: 0.7,
                    maxTokens: 64,
                    topP: 0.9))
                .toList(),
            throwsA(predicate((e) =>
                e is AiProviderException &&
                e.kind == AiFailureKind.unauthorized)));
      } finally {
        await s.stop();
      }
    });

    test('unreachable cloud endpoint fails gracefully', () async {
      final s = await FakeOpenAiServer.start();
      final url = s.baseUrl;
      await s.stop();
      final keys = InMemoryCloudKeyStore();
      await keys.write(
          'soulcare_cloud_key_custom', 'k');
      final config = AiConfig(
          mode: AiMode.cloud,
          cloud: CloudAiSettings(
              provider: CloudProviderKind.custom,
              endpoint: url,
              model: 'm'));
      final p =
          _cloudProvider(config: config, keys: keys);
      expect((await p.testConnection()).ok, isFalse);
    });
  });

  group('cloud provider (Gemini REST)', () {
    test('valid key lists models and streams', () async {
      final s = await FakeGeminiServer.start();
      try {
        final keys = InMemoryCloudKeyStore();
        await keys.write(
            'soulcare_cloud_key_gemini', 'test-gemini-key');
        final config = AiConfig(
            mode: AiMode.cloud,
            cloud: CloudAiSettings(
                provider: CloudProviderKind.gemini,
                endpoint: s.baseUrl,
                model: 'gemini-2.0-flash'));
        final p = _cloudProvider(
            config: config, keys: keys);
        final st = await p.testConnection();
        expect(st.ok, isTrue);
        expect(st.modelCount, 1);
        expect(st.activeModelId, 'models/gemini-2.0-flash');
        expect(p.providerLabel, contains('Gemini'));
        final text = await p
            .generateResponse(messages: const [
              AiMessage(
                  role: AiRole.system,
                  content: 'sys'),
              AiMessage(
                  role: AiRole.user, content: 'hi')
            ], options: const AiGenerationOptions(
                temperature: 0.7, maxTokens: 64, topP: 0.9))
            .where((c) => !c.done)
            .map((c) => c.text)
            .join();
        expect(text, 'Hello SoulCare');
        // System prompt travels as system_instruction, not as a
        // user turn.
        final body = s.seenRequests.single;
        expect(body['system_instruction'], isNotNull);
        expect(
            (body['contents'] as List).any((m) =>
                m['role'] == 'user' &&
                (m['parts'] as List).any((pt) =>
                    (pt['text'] as String).contains('hi'))),
            isTrue);
      } finally {
        await s.stop();
      }
    });

    test('wrong key is unauthorized', () async {
      final s = await FakeGeminiServer.start();
      try {
        final keys = InMemoryCloudKeyStore();
        await keys.write(
            'soulcare_cloud_key_gemini', 'wrong');
        final config = AiConfig(
            mode: AiMode.cloud,
            cloud: CloudAiSettings(
                provider: CloudProviderKind.gemini,
                endpoint: s.baseUrl,
                model: 'gemini-2.0-flash'));
        final p = _cloudProvider(
            config: config, keys: keys);
        expect((await p.testConnection()).ok, isFalse);
      } finally {
        await s.stop();
      }
    });
  });

  group('domain guard', () {
    final guard = AiDomainGuard();

    test('relevant SoulCare/health questions are allowed', () {
      for (final q in [
        'How was my sleep this week?',
        'What changed this month?',
        'How consistent was my exercise?',
        'What were my stress patterns?',
        'What experiments have I completed?',
        'How has my wellness score changed?',
        'How much sleep do adults generally need?',
        'What are common reasons people feel tired?',
        'What are the benefits of resistance training?',
        'How can I improve sleep hygiene?',
        'What is insulin resistance?',
        'Why does dehydration make me feel tired?',
        'How did my sleep change this month?',
        'What does this health term mean?',
        'Can stress affect sleep?',
        'What is a stress fracture?',
        'Why am I tired?',
        'What causes headaches?',
        'How was my sleep this week?',
      ]) {
        expect(guard.classify(q), AiDomain.allowed,
            reason: 'should allow: $q');
      }
    });

    test('unrelated questions are out of scope', () {
      for (final q in [
        'How do I fix my leaking car?',
        'Write me a Python game.',
        "What's the best gaming laptop?",
        'Who won the football match?',
        'Tell me a joke.',
        'Write my resume.',
        'How do I pirate a movie?',
        'My car has stress fractures in the chassis.',
      ]) {
        expect(guard.classify(q), AiDomain.outOfScope,
            reason: 'should reject: $q');
      }
    });

    test('ambiguous questions are not refused outright', () {
      expect(guard.classify('What time is it?'),
          anyOf(AiDomain.ambiguous, AiDomain.allowed));
      // Genuinely ambiguous phrasing gets health-context framing.
      expect(guard.classify('Why do I feel off lately?'),
          anyOf(AiDomain.allowed, AiDomain.ambiguous));
    });

    test('out-of-scope answers never reach the provider', () async {
      final local = await FakeOpenAiServer.start();
      final cloud = await FakeOpenAiServer.start();
      try {
        final keys = InMemoryCloudKeyStore();
        final config = AiConfig(
            mode: AiMode.local,
            local: LocalAiSettings(
                serverUrl: local.baseUrl));
        final localP = LocalAiProvider(
            configOf: () => config);
        final cloudP = CloudAiProvider(
            configOf: () => config,
            apiKeyOf: () =>
                AiSecureStore(store: keys)
                    .readKey(config.cloud.provider));
        final conn = AiConnectionManager(
            provider: localP,
            ttlOf: () => const Duration(seconds: 60));
        final svc = _serviceFor(
            local: localP,
            cloud: cloudP,
            config: config,
            connection: conn);
        final conv = await const AiChatRepository()
            .createConversation('t');
        final id = conv.fold(
            onSuccess: (c) => c.id, onFailure: (_) => '');
        final beforeLocal = local.requestCount;
        final beforeCloud = cloud.requestCount;
        final texts = <String>[];
        await for (final t in svc.answer(
            conversationId: id,
            question: 'Write me a Python game.')) {
          texts.add(t);
        }
        expect(texts.join(),
            contains('SoulCare AI, so I focus'));
        expect(local.requestCount, beforeLocal);
        expect(cloud.requestCount, beforeCloud);
      } finally {
        await local.stop();
        await cloud.stop();
      }
    });
  });

  group('soulcare context + personal data', () {
    Future<void> seedWeek() async {
      final daily = DailyHealthRepository();
      final stress = StressRepository();
      final now = DateTime.now();
      for (var i = 0; i < 7; i++) {
        final d = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: i));
        await daily.save(DailyHealthEntry(
          date: _key(d),
          sleepHours: 7,
          exerciseMinutes: 20,
          waterGlasses: 6,
          meditationMinutes: 5,
        ));
        if (i.isEven) {
          await stress.save(StressEntry(
            id: 's$i',
            date: _key(d),
            mood: Mood.okay,
            createdAt: now,
          ));
        }
      }
    }

    SoulCareAiService serviceFor(FakeOpenAiServer s) {
      final config = _localConfig(s.baseUrl);
      final localP =
          LocalAiProvider(configOf: () => config);
      final keys = InMemoryCloudKeyStore();
      final cloudP = CloudAiProvider(
          configOf: () => config,
          apiKeyOf: () => AiSecureStore(store: keys)
              .readKey(config.cloud.provider));
      return _serviceFor(
          local: localP,
          cloud: cloudP,
          config: config,
          connection: AiConnectionManager(
              provider: localP,
              ttlOf: () => const Duration(seconds: 60)));
    }

    test('sleep question uses only sleep-related structured context',
        () async {
      await seedWeek();
      final s = await FakeOpenAiServer.start();
      try {
        final svc = serviceFor(s);
        final conv = await const AiChatRepository()
            .createConversation('t');
        final id = conv.fold(
            onSuccess: (c) => c.id, onFailure: (_) => '');
        await svc
            .answer(
                conversationId: id,
                question: 'How was my sleep this week?')
            .toList();
        final body =
            s.seenRequests.single['messages'] as List;
        final blob = jsonEncode(body);
        expect(blob, contains('sleep_trend'));
        expect(svc.lastBasis, contains('Based on'));
        // Private stores never included in the STRUCTURED CONTEXT
        // message (index 1). The system prompt itself legitimately
        // contains words like "medication"/"dosage" in its safety
        // rules — that is instructions, not user data.
        final contextMsg = jsonEncode(body[1]);
        for (final forbidden in [
          'journal_entries',
          'medical_documents',
          'contentHash',
          'localPath',
          'dosage',
          'appointments',
          'user_profile',
          'emergencyName',
          'emergencyContact',
        ]) {
          expect(contextMsg.contains(forbidden), isFalse,
              reason: 'leaked: $forbidden');
        }
      } finally {
        await s.stop();
      }
    });

    test('no health data answers honestly with basis empty',
        () async {
      final s = await FakeOpenAiServer.start();
      try {
        final svc = serviceFor(s);
        final conv = await const AiChatRepository()
            .createConversation('t');
        final id = conv.fold(
            onSuccess: (c) => c.id, onFailure: (_) => '');
        final texts = <String>[];
        await for (final t in svc.answer(
            conversationId: id,
            question: 'How was my sleep this week?')) {
          texts.add(t);
        }
        expect(texts.join().isNotEmpty, isTrue);
        final body =
            s.seenRequests.single['messages'] as List;
        expect(jsonEncode(body), contains('sleep_trend'));
      } finally {
        await s.stop();
      }
    });

    test('suggestions follow available data', () async {
      final s = await FakeOpenAiServer.start();
      try {
        final svc = serviceFor(s);
        expect(await svc.suggestions(),
            ['What experiments have I completed?']);
        await seedWeek();
        final with_ = await svc.suggestions();
        expect(with_, contains('How was my sleep this week?'));
      } finally {
        await s.stop();
      }
    });
  });

  group('data safety (architectural)', () {
    test('AI layer exposes no write tools', () {
      for (final path in [
        'lib/core/ai/soulcare_ai_service.dart',
        'lib/core/ai/ai_context.dart',
        'lib/core/ai/local_ai_provider.dart',
        'lib/core/ai/cloud_ai_provider.dart',
        'lib/core/ai/openai_compat_client.dart',
      ]) {
        final src = File(path).readAsStringSync();
        for (final verb in [
          '.delete(',
          '.clear()',
          '.update(',
          '.save(',
          '.put(',
          'DROP ',
          'DELETE FROM',
          'runSql',
          'execute(',
          'Process.',
          'dart:io',
        ]) {
          // dart:io in tests only; providers use package:http.
          expect(src.contains(verb), isFalse,
              reason: '$path contains write/exec surface: $verb');
        }
      }
    });

    test('system prompt forbids invention, diagnosis, med changes',
        () {
      expect(AiPrompts.system, contains('Never invent user data'));
      expect(AiPrompts.system, contains('read-only'));
      expect(
          AiPrompts.system,
          contains(
              'never tell the user to stop or change prescribed medication'
                  .toLowerCase()));
      expect(AiPrompts.system.toLowerCase(),
          contains('not a replacement for professional medical care'));
      expect(AiPrompts.system, isNot(contains('You are a doctor')));
    });
  });

  group('privacy', () {
    test('cloud key never lands in config JSON, history, or exports',
        () async {
      const rawKey = 'sk-test-ABCDEF1234567890';
      final keys = InMemoryCloudKeyStore();
      final repo = AiConfigRepository(
          secure: AiSecureStore(store: keys));
      await repo.save(
          const AiConfig(mode: AiMode.cloud));
      await repo.saveCloudKey(
          CloudProviderKind.gemini, rawKey);
      // Config JSON (what Hive + exports would carry).
      final loaded =
          (await repo.load()).fold(
              onSuccess: (c) => c,
              onFailure: (_) => const AiConfig());
      expect(
          jsonEncode(loaded.toJson()).contains(rawKey),
          isFalse);
      final boxRaw = LocalDatabase.settingsBox
          .values
          .map((v) => jsonEncode(v))
          .join();
      expect(boxRaw.contains(rawKey), isFalse);
      // Chat history after a cloud answer.
      final s = await FakeGeminiServer.start(
          validKey: rawKey);
      try {
        final config = AiConfig(
            mode: AiMode.cloud,
            cloud: CloudAiSettings(
                provider: CloudProviderKind.gemini,
                endpoint: s.baseUrl,
                model: 'gemini-2.0-flash'));
        final localP =
            LocalAiProvider(configOf: () => config);
        final cloudP = CloudAiProvider(
            configOf: () => config,
            apiKeyOf: () => AiSecureStore(store: keys)
                .readKey(config.cloud.provider));
        final svc = _serviceFor(
            local: localP,
            cloud: cloudP,
            config: config,
            connection: AiConnectionManager(
                provider: cloudP,
                ttlOf: () => const Duration(seconds: 60)));
        final conv = await const AiChatRepository()
            .createConversation('t');
        final id = conv.fold(
            onSuccess: (c) => c.id, onFailure: (_) => '');
        await svc
            .answer(
                conversationId: id,
                question: 'How can I improve sleep hygiene?')
            .toList();
        final history = (await const AiChatRepository()
                .getMessages(id))
            .fold(
                onSuccess: (l) => l, onFailure: (_) => []);
        expect(
            history.map((m) => m.content).join().contains(rawKey),
            isFalse);
        expect(
            LocalDatabase.aiMessagesBox.values
                .map((v) => jsonEncode(v))
                .join()
                .contains(rawKey),
            isFalse);
      } finally {
        await s.stop();
      }
      // Masked display never reveals the key.
      final masked = await repo
          .maskedCloudKey(CloudProviderKind.gemini);
      expect(masked.contains(rawKey), isFalse);
      expect(masked, contains('7890'));
    });

    test('local mode makes zero cloud calls', () async {
      final local = await FakeOpenAiServer.start();
      final cloud = await FakeOpenAiServer.start();
      try {
        final keys = InMemoryCloudKeyStore();
        final config = AiConfig(
            mode: AiMode.local,
            local: LocalAiSettings(
                serverUrl: local.baseUrl));
        final localP = LocalAiProvider(
            configOf: () => config);
        final cloudP = CloudAiProvider(
            configOf: () => config,
            apiKeyOf: () =>
                AiSecureStore(store: keys)
                    .readKey(config.cloud.provider));
        final svc = _serviceFor(
            local: localP,
            cloud: cloudP,
            config: config,
            connection: AiConnectionManager(
                provider: localP,
                ttlOf: () => const Duration(seconds: 60)));
        final conv = await const AiChatRepository()
            .createConversation('t');
        final id = conv.fold(
            onSuccess: (c) => c.id, onFailure: (_) => '');
        final before = cloud.requestCount;
        await svc
            .answer(
                conversationId: id,
                question: 'How can I improve sleep hygiene?')
            .toList();
        expect(cloud.requestCount, before);
      } finally {
        await local.stop();
        await cloud.stop();
      }
    });
  });

  group('mode switching + persistence', () {
    test('switching providers keeps history with accurate tags',
        () async {
      final local = await FakeOpenAiServer.start(
          tokens: ['local says hi']);
      final gemini = await FakeGeminiServer.start(
          validKey: 'k1', tokens: ['cloud says hi']);
      try {
        final keys = InMemoryCloudKeyStore();
        await keys.write(
            'soulcare_cloud_key_gemini', 'k1');
        final secure = AiSecureStore(store: keys);
        final prov = AiChatProvider(
            configRepo:
                AiConfigRepository(secure: secure),
            secure: secure);
        await prov.init();
        expect(
            await prov.saveConfig(AiConfig(
                mode: AiMode.local,
                local: LocalAiSettings(
                    serverUrl: local.baseUrl))),
            isTrue);
        await prov.send('How can I improve sleep hygiene?');
        expect(prov.error, isNull);
        expect(prov.messages.length, 2);
        expect(
            prov.messages.last.providerUsed, 'local');
        // Switch to cloud: same conversation, history intact.
        await prov.saveConfig(prov.config.copyWith(
            mode: AiMode.cloud,
            cloud: CloudAiSettings(
                provider: CloudProviderKind.gemini,
                endpoint: gemini.baseUrl,
                model: 'gemini-2.0-flash'),
            cloudConsentAcknowledged: true));
        await prov.checkConnection();
        expect(prov.connection.isConnected, isTrue);
        final convId = prov.activeId!;
        await prov.send(
            'What are the benefits of resistance training?');
        expect(prov.error, isNull);
        expect(prov.activeId, convId);
        expect(prov.messages.length, 4);
        expect(prov.messages.last.content,
            contains('cloud says hi'));
        expect(prov.messages.last.providerUsed,
            'cloud:gemini');
        expect(prov.messages.first.content,
            contains('sleep hygiene'));
        // Indicator never mislabels.
        expect(prov.providerIndicator, contains('Cloud'));
        prov.dispose();
      } finally {
        await local.stop();
        await gemini.stop();
      }
    });

    test('conversations round-trip with provider tags', () async {
      const repo = AiChatRepository();
      final created = await repo.createConversation(
          'Hello SoulCare.',
          providerUsed: 'local');
      final conv = created.fold(
          onSuccess: (c) => c, onFailure: (_) => null)!;
      expect(conv.providerUsed, 'local');
      await repo.addMessage(
          conversationId: conv.id,
          role: AiRole.user,
          content: 'hi',
          providerUsed: 'local');
      await repo.addMessage(
          conversationId: conv.id,
          role: AiRole.assistant,
          content: 'hello back',
          providerUsed: 'cloud:gemini');
      var msgs = (await repo.getMessages(conv.id))
          .fold(onSuccess: (l) => l, onFailure: (_) => []);
      expect(msgs.map((m) => m.role),
          [AiRole.user, AiRole.assistant]);
      expect(msgs.last.providerUsed, 'cloud:gemini');
      await repo.touchProvider(conv.id, 'cloud:gemini');
      var all = (await repo.getConversations())
          .fold(onSuccess: (l) => l, onFailure: (_) => []);
      expect(all.single.providerUsed, 'cloud:gemini');
      // Legacy records without tags migrate to local.
      expect(
          AiConversation.fromJson({
            'id': 'x',
            'title': 't',
            'createdAt':
                DateTime.now().toIso8601String(),
            'updatedAt':
                DateTime.now().toIso8601String(),
          }).providerUsed,
          'local');
      await repo.renameConversation(conv.id, 'Renamed');
      all = (await repo.getConversations())
          .fold(onSuccess: (l) => l, onFailure: (_) => []);
      expect(all.single.title, 'Renamed');
      expect(all.single.providerUsed, 'cloud:gemini');
      await repo.clearMessages(conv.id);
      msgs = (await repo.getMessages(conv.id))
          .fold(onSuccess: (l) => l, onFailure: (_) => []);
      expect(msgs, isEmpty);
      await repo.deleteConversation(conv.id);
      all = (await repo.getConversations())
          .fold(onSuccess: (l) => l, onFailure: (_) => []);
      expect(all, isEmpty);
    });

    test('provider send persists both turns end to end', () async {
      final s = await FakeOpenAiServer.start();
      final keys = InMemoryCloudKeyStore();
      final secure = AiSecureStore(store: keys);
      final prov = AiChatProvider(
          configRepo:
              AiConfigRepository(secure: secure),
          secure: secure);
      try {
        await prov.init();
        expect(
            await prov.saveConfig(_localConfig(s.baseUrl)),
            isTrue);
        await prov.send('How can I improve sleep hygiene?');
        expect(prov.error, isNull);
        expect(
            prov.messages
                .where((m) => m.role == AiRole.user)
                .length,
            1);
        expect(
            prov.messages
                .where((m) => m.role == AiRole.assistant)
                .length,
            1);
        expect(prov.messages.last.content, 'Hello SoulCare');
        expect(prov.turn, AiTurnState.completed);
      } finally {
        prov.dispose();
        await s.stop();
      }
    });
  });

  group('config', () {
    test('defaults, clamps, validation, placement, migration', () {
      const d = AiConfig();
      expect(d.mode, AiMode.local);
      expect(d.local.serverUrl,
          'http://127.0.0.1:11434/v1');
      expect(d.local.temperature, 0.7);
      expect(d.cloud.provider, CloudProviderKind.gemini);
      final clamped = LocalAiSettings.fromJson(const {
        'temperature': 99,
        'maxTokens': 1,
      });
      expect(clamped.temperature, 2.0);
      expect(clamped.maxTokens, 32);
      final round = AiConfig.fromJson(
          const AiConfig().copyWith(mode: AiMode.cloud).toJson());
      expect(round.mode, AiMode.cloud);
      expect(
          AiConfig.fromJson(const {
            'serverUrl': 'http://127.0.0.1:8080/v1'
          }).local.serverUrl,
          'http://127.0.0.1:11434/v1');
      // Pre-rebuild flat schema migrates instead of dropping settings.
      expect(validateServerUrl('not a url'), isNotNull);
      expect(validateServerUrl('ftp://x'), isNotNull);
      expect(
          validateServerUrl('http://127.0.0.1:11434/v1'),
          isNull);
      expect(classifyServerUrl('http://127.0.0.1:8080/v1'),
          ServerPlacement.onDevice);
      expect(classifyServerUrl('http://192.168.1.5:8080/v1'),
          ServerPlacement.lan);
      expect(classifyServerUrl('https://example.com/v1'),
          ServerPlacement.remote);
      expect(
          normalizeServerUrl('http://127.0.0.1:11434'),
          'http://127.0.0.1:11434/v1');
      expect(
          normalizeServerUrl(
              'https://generativelanguage.googleapis.com/v1beta'),
          'https://generativelanguage.googleapis.com/v1beta');
      expect(
          CloudAiSettings.defaultEndpointFor(
              CloudProviderKind.openAI),
          'https://api.openai.com/v1');
      expect(
          const AiModel(id: 'gemma-4-e2b-it.gguf')
              .displayName,
          'gemma 4 e2b it');
      expect(
          const AiModel(id: 'models/gemini-2.0-flash')
              .displayName,
          'gemini 2.0 flash');
      expect(AiPrompts.system, contains('Never invent user data'));
    });

    test('secure store masks keys and forgets on delete', () async {
      final store =
          AiSecureStore(store: InMemoryCloudKeyStore());
      expect(await store.hasKey(CloudProviderKind.gemini),
          isFalse);
      await store.writeKey(
          CloudProviderKind.gemini, 'sk-test-ABCDEFGH1234');
      expect(await store.hasKey(CloudProviderKind.gemini),
          isTrue);
      final masked = await store
          .maskedKey(CloudProviderKind.gemini);
      expect(masked, contains('1234'));
      expect(masked, isNot(contains('ABCDEFGH')));
      await store.deleteKey(CloudProviderKind.gemini);
      expect(await store.hasKey(CloudProviderKind.gemini),
          isFalse);
    });
  });
}
