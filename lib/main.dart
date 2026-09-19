import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const FlusApp());

String? validateUrl(String value) {
  if (value.trim().isEmpty) return 'Вставьте Yandex / Mail.ru URL.';
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return 'Нужна корректная ссылка, начинающаяся с https://';
  }
  if (!['disk.yandex.ru', 'disk.yandex.com', 'cloud.mail.ru', 'doc.mail.ru'].contains(uri.host)) {
    return 'Используйте ссылку disk.yandex.ru, cloud.mail.ru или doc.mail.ru.';
  }
  return null;
}

class FlusApp extends StatelessWidget {
  const FlusApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FLUS TEST',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF7F7F4),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF242424),
        primary: const Color(0xFF242424),
        surface: const Color(0xFFF7F7F4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0E0DB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0E0DB)),
        ),
        contentPadding: const EdgeInsets.all(18),
      ),
    ),
    home: const LauncherPage(),
  );
}

class LauncherPage extends StatefulWidget {
  const LauncherPage({super.key});
  @override
  State<LauncherPage> createState() => _LauncherPageState();
}

class _LauncherPageState extends State<LauncherPage>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('com.openflux.launcher/control');
  final url = TextEditingController();
  final form = GlobalKey<FormState>();
  Timer? timer;
  bool hidden = true,
      busy = false,
      debug = false,
      loading = true,
      polling = false;
  String state = 'stopped', detail = 'Готов к запуску', error = '';
  List<String> logs = [];
  bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get active => ['starting', 'running', 'stopping'].contains(state);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialize();
  }

  Future<void> initialize() async {
    if (android) {
      try {
        final saved = await channel.invokeMethod<String>('loadUrl');
        if (mounted) url.text = saved ?? '';
      } on PlatformException {
        if (mounted) {
          error = 'Не удалось прочитать сохранённую ссылку. Введите её заново.';
        }
      }
      await refresh();
      timer = Timer.periodic(
        const Duration(milliseconds: 800),
        (_) => refresh(),
      );
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> refresh() async {
    if (!android || polling || !mounted) return;
    polling = true;
    try {
      final data = await channel.invokeMapMethod<String, dynamic>('snapshot');
      if (mounted && data != null) {
        setState(() {
          state = data['state'] as String? ?? 'stopped';
          detail = data['detail'] as String? ?? '';
          logs = List<String>.from(data['logs'] as List? ?? []);
        });
      }
    } on PlatformException {
      if (mounted) {
        setState(
          () => error = 'Не удалось получить состояние Android service.',
        );
      }
    } finally {
      polling = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.resumed) refresh();
  }

  Future<void> start() async {
    if (!form.currentState!.validate()) return;
    if (!android) {
      message(
        'Запуск OpenFlux доступен только в Android APK. Это превью интерфейса.',
      );
      return;
    }
    final uri = Uri.parse(url.text.trim());
    if (!((uri.path.startsWith('/edit/d/') && uri.path.length > 8) || (uri.host == 'cloud.mail.ru' && uri.path.contains('/edit/')))) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Это не edit-ссылка'),
          content: const Text(
            'Похоже, это публичная ссылка для просмотра или другой формат. OpenFlux может не подключиться. Убедитесь, что ссылка позволяет редактирование.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Исправить'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Продолжить'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await channel.invokeMethod('start', {
        'url': url.text.trim(),
        'debug': debug,
      });
      await refresh();
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => error = e.message ?? 'Не удалось запустить FLUS.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> stop() async {
    setState(() => busy = true);
    try {
      await channel.invokeMethod('stop');
      await refresh();
    } on PlatformException {
      if (mounted) setState(() => error = 'Не удалось остановить сервис.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) message('Скопировано');
  }

  Future<void> clear() async {
    if (android) await channel.invokeMethod('clearLogs');
    if (mounted) setState(() => logs = []);
  }

  @override
  void dispose() {
    timer?.cancel();
    url.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      'starting' => 'Запускается',
      'running' => 'Работает',
      'stopping' => 'Останавливается',
      'error' => 'Ошибка',
      _ => 'Остановлен',
    };
    final indicator = state == 'running'
        ? const Color(0xFF36775B)
        : state == 'error'
        ? Colors.red
        : const Color(0xFF999A91);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Flexible(
                      flex: 4,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'FLUS',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -3,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE5D5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'TEST',
                        style: TextStyle(
                          color: Color(0xFFB1491A),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.power_settings_new_rounded,
                      color: Color(0xFFAAA99F),
                      size: 26,
                    ),
                  ],
                ),
                const Text(
                  'Маленький мост. Ваш маршрут.',
                  style: TextStyle(fontSize: 15, color: Color(0xFF74756D)),
                ),
                const SizedBox(height: 24),
                if (!android) ...[
                  notice(
                    Icons.desktop_windows_outlined,
                    'Веб-превью',
                    'Здесь можно посмотреть интерфейс. Реальный SOCKS5 запускается только в Android APK.',
                  ),
                  const SizedBox(height: 18),
                ],
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE4E4DF)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: indicator,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              detail,
                              style: const TextStyle(
                                color: Color(0xFF74756D),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (state == 'starting' || state == 'stopping')
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                const Text(
                  'Yandex Docs / Mail.ru URL',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Form(
                  key: form,
                  child: TextFormField(
                    controller: url,
                    enabled: !active && !loading && !busy,
                    obscureText: hidden,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.url,
                    autofillHints: const [],
                    validator: (value) => validateUrl(value ?? ''),
                    decoration: InputDecoration(
                      hintText: 'https://...',
                      suffixIcon: IconButton(
                        tooltip: hidden ? 'Показать URL' : 'Скрыть URL',
                        onPressed: () => setState(() => hidden = !hidden),
                        icon: Icon(
                          hidden
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 13,
                      color: Color(0xFF828378),
                    ),
                    SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Ссылка хранится на устройстве в зашифрованном виде',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF828378),
                        ),
                      ),
                    ),
                  ],
                ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: active || busy || loading ? null : start,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text(
                          'Start',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: active && state != 'stopping' && !busy
                            ? stop
                            : null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text(
                          'Stop',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 10, 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEEEEA),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ЛОКАЛЬНЫЙ SOCKS5',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.8,
                                color: Color(0xFF797B71),
                              ),
                            ),
                            const SizedBox(height: 7),
                            const FittedBox(
                              child: Text(
                                '127.0.0.1:1080',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Без логина и пароля',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF797B71),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Скопировать SOCKS5',
                        onPressed: () => copy('127.0.0.1:1080'),
                        icon: const Icon(Icons.copy_outlined, size: 21),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                notice(
                  Icons.route_outlined,
                  'Не забудьте исключение',
                  'Перед включением VPN исключите FLUS (com.openflux.launcher) из туннеля RX-PRO / NekoBox. Иначе возникнет петля соединения.',
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Как подключить',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  children: const [
                    Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        '1. Exit-node на VPS должен работать с тем же URL.\n2. Нажмите Start в FLUS.\n3. Создайте SOCKS5-профиль в RX-PRO / NekoBox: 127.0.0.1, порт 1080, логин и пароль пустые.\n4. Исключите FLUS из VPN и включите этот профиль.\n5. Откройте api.ipify.org в браузере: ожидается IP VPS.\n\n«Работает» подтверждает локальный SOCKS5, а не доступность VPS. Транспорт — TCP/IPv4; UDP не поддерживается. DNS и защита от утечек настраиваются во внешнем VPN-клиенте. FLUS сам не блокирует прямой трафик при обрыве.',
                        style: TextStyle(
                          height: 1.6,
                          fontSize: 13,
                          color: Color(0xFF65665E),
                        ),
                      ),
                    ),
                  ],
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Журнал · ${logs.length}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: clear,
                          icon: const Icon(Icons.delete_outline, size: 17),
                          label: const Text('Очистить'),
                        ),
                        TextButton.icon(
                          onPressed: logs.isEmpty
                              ? null
                              : () => copy(logs.join('\n')),
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Копировать'),
                        ),
                      ],
                    ),
                    Container(
                      width: double.infinity,
                      height: 190,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF242424),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: SelectableText(
                          logs.isEmpty
                              ? 'События появятся после запуска.'
                              : logs.join('\n'),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            height: 1.6,
                            color: Color(0xFFDADCD2),
                          ),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Подробные события',
                        style: TextStyle(fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Без URL, cookies и токенов',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: debug,
                      onChanged: active
                          ? null
                          : (value) => setState(() => debug = value),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text(
                  'FLUS / 0.1.0-test.1',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: Color(0xFF8F9086),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Тестовая сборка. Возможны сбои.\nТолько для образовательных целей. Используйте на своих устройствах и в сетях, где у вас есть разрешение.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.6,
                    color: Color(0xFF93948B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget notice(IconData icon, String title, String text) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0E5),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFFAD5A2F)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Color(0xFF7D604D),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
