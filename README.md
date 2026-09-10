# FLUS — OpenFlux Launcher (TEST)

**Экспериментальный Android APK, не стабильный VPN-клиент.** FLUS запускает встроенный OpenFlux без Termux, root, Go и Git на телефоне. Обычный RX-PRO 1.5.1 не изменяется.

[Скачать APK во вкладке Releases](https://github.com/cwash797-cmd/FLUS/releases) — выбирайте `FLUS-TEST-arm64-v8a.apk`. Тестовые публикации помечены **Pre-release**, не Latest. Требуются Android 8.0+ и поддержка **arm64-v8a**. Фактическую работу на вашем устройстве и с вашим оператором нужно проверить.

## Как пользоваться

1. Установите FLUS TEST из Releases.
2. Вставьте Yandex Docs **edit-ссылку** (`https://disk.yandex.ru/edit/d/…` или `.com`). Ссылка является секретом.
3. Разрешите уведомления и нажмите **Start**.
4. Дождитесь статуса **Работает** — он означает готовность локального SOCKS5, **не подтверждает доступ к VPS**.
5. В RX-PRO / NekoBox создайте SOCKS5-профиль:
   - Host: `127.0.0.1`
   - Port: `1080`
   - Username и Password: пустые.
6. **До включения VPN исключите FLUS из VPN-туннеля** (режим обхода для приложения). Release package: `com.openflux.launcher`; debug package: `com.openflux.launcher.debug`. В режиме списка разрешённых приложений FLUS не должен входить в список.
7. Включите созданный профиль в RX-PRO / NekoBox.
8. Откройте `https://api.ipify.org` в браузере: должен отображаться адрес вашего VPS.
9. Нажмите **Stop**, чтобы завершить OpenFlux и освободить порт. VPN-клиент останавливается отдельно.

Без исключения FLUS возникает петля: OpenFlux → VPN → OpenFlux. Исключить приложение из другого VPN автоматически FLUS не может.

Exit-node уже должен работать с **тем же документом**, что указан на телефоне. FLUS не устанавливает сервер и не создаёт документы. Upstream рассчитан на старый совместимый редактор Yandex; публичная `/i/` ссылка или новый редактор могут не работать.

## Возможности

- Встроенный Android executable, никаких загрузок бинарника при запуске.
- Foreground service, уведомление со Stop, контроль живого процесса и SOCKS5-handshake.
- Android Keystore AES-256-GCM: в SharedPreferences только шифротекст, резервное копирование отключено.
- Секрет передаётся в OpenFlux через stdin, не в аргументах процесса или Intent.
- Только разрешённые обезличенные события в логах, максимум 400 строк, копирование/очистка.
- URL скрыт по умолчанию; скриншоты/содержимое окна в Recents защищены FLAG_SECURE.
- Никакой аналитики, регистрации, рекламы, crash reporting или собственного VPNService.
- Иконка FLUS, TEST на экране и в названии приложения.

## Ограничения и безопасность

- **TCP/IPv4 only. UDP, QUIC и целевые IPv6-only ресурсы не поддерживаются.** Подключение самого транспорта к Yandex может использовать доступные адреса мобильной сети.
- Встроенный upstream `DialTCP` разрешает домены на клиенте. Передача домена в SOCKS5 **не гарантирует DNS на VPS**. DNS и IPv6 leak protection настраиваются во внешнем VPN-клиенте; отсутствие утечек этой оболочкой не обещается. Предпочтительно разрешать целевые адреса внутри правильно настроенного RX-PRO и передавать IPv4 в SOCKS5.
- **FLUS не имеет kill switch:** при сбое блокировка прямого трафика зависит от RX-PRO/NekoBox и системного Always-on/lockdown. Совместимость lockdown с исключённым FLUS требует отдельной проверки.
- Loopback SOCKS5 без пароля потенциально доступен другим приложениям устройства с сетевыми правами. Не используйте на недоверенном устройстве. Не публикуйте порт на `0.0.0.0`.
- TLS-соединение с Yandex не является отдельным сквозным шифрованием FLUS ↔ VPS. Upstream не добавляет независимую аутентификацию/шифрование туннеля; используйте HTTPS конечных сервисов и считайте ссылку секретом.
- Foreground service и wakelock увеличивают расход батареи и не гарантируют защиту от остановки ОС/OEM. После force-stop запуск только вручную. Автозапуска при загрузке нет.
- При падении дочернего процесса FLUS показывает ошибку; автоматический бесконечный перезапуск процесса не выполняется. Транспорт имеет ограниченную задержкой логику reconnect.
- Порт занят: остановите другой FLUS/прокси. Если VPS не отвечает, зелёный статус локального SOCKS5 всё равно возможен.
- Не публикуйте URL, cookies, токены. При утечке замените документ и ссылку на обеих сторонах.

## Исходники и версия ядра

OpenFlux core version: **commit `461905369bd8f44ad2aacff240540d6a01d38c4d`** из [p1neappleXpress/OpenFlux](https://github.com/p1neappleXpress/OpenFlux).

В `vendor/` включены соответствующие исходники с небольшими изменениями FLUS:

- `--url-stdin`, allowlist событий вместо сырых логов;
- маркер готовности после bind и корректный фрагментированный SOCKS5 parsing;
- ограничение числа SOCKS5-соединений и таймаут рукопожатия;
- завершение Android child при исчезновении родителя;
- задержка reconnect, таймауты WebSocket, проверки JSON и лимит размера страницы/сообщений.

Формат Yandex-транспорта не менялся. Однако совместимость с вашим exit-node нужно подтвердить реальным тестом.

UI — Flutter, Android service — Kotlin. Здесь не чистый Gradle-шаблон: сначала подготовьте Flutter и соберите ядро.

```text
lib/main.dart                              интерфейс
android/app/src/main/kotlin/com/openflux/launcher/  service, bridge, secrets
vendor/                                    OpenFlux и локальные изменения
scripts/build-core.sh                      сборка Android PIE executable
android/app/src/main/jniLibs/arm64-v8a/libopenflux.so  результат, не хранится в Git
.github/workflows/build-apk.yml             CI
```

`libopenflux.so` — **PIE executable**, а не JNI-библиотека. PackageManager извлекает его в `nativeLibraryDir`; сервис запускает файл оттуда через ProcessBuilder. `extractNativeLibs=true`, legacy native packaging и запрет stripping этого файла обязательны.

## Сборка

Зафиксированные инструменты: Flutter **3.35.4**, Dart **3.9.2**, Java **17**, Go **1.27.1**, Android SDK/Build Tools **35 / 35.0.0**, NDK **27.0.12077973**. Native API minimum **26**, выравнивание ELF LOAD **16 КБ**. Наличие выравнивания само по себе не заменяет тест на устройстве с 16-КБ страницами.

```bash
export ANDROID_HOME=/path/to/android-sdk
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/27.0.12077973"
# flutter и go должны быть в PATH
flutter pub get
(cd vendor && go test ./socks5)
bash scripts/build-core.sh
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`.

После подготовки ядра и `flutter pub get` также работают:

```bash
cd android
./gradlew assembleDebug
./gradlew :app:testDebugUnitTest
# Требует android/key.properties и отдельный ключ FLUS:
./gradlew assembleRelease
```

### Подписанная тестовая release-сборка

Не используйте ключ RX-PRO. Сохраните отдельный ключ FLUS в безопасном месте и используйте его во всех тестовых release-обновлениях. Keystore и пароли **никогда не коммитить**.

В `android/key.properties` (игнорируется Git):

```properties
storeFile=../release-key.jks
storePassword=YOUR_PRIVATE_PASSWORD
keyAlias=YOUR_ALIAS
keyPassword=YOUR_PRIVATE_PASSWORD
```

Путь `storeFile` относительно `android/app`. Файл ключа — `android/release-key.jks`.

```bash
flutter build apk --release --target-platform android-arm64
```

Результат: `build/app/outputs/flutter-apk/app-release.apk`. Это release-режим компилятора, **не заявление о стабильности продукта**. У приложения остаются TEST и версия с `test`.

### GitHub Actions

Каждый push и PR: Flutter/Go/Kotlin tests, сборка debug, Artifacts. Tag `v*` или публикация release: дополнительно подписанный TEST APK, Artifacts и GitHub **Pre-release**, `Latest=false`. При автоматической загрузке action использует только `GITHUB_TOKEN` с правами contents:write в publish job.

Секреты репозитория:

- `FLUS_KEYSTORE_BASE64` — base64 отдельного keystore FLUS;
- `FLUS_SIGNING_JSON` — JSON со `storePassword`, `keyPassword`, `keyAlias`.

Скрипт `scripts/ci-signing.py` восстанавливает файлы без вывода значений; CI удаляет их в конце. Fork PR не получает signing secrets. Отсутствие ключа вызывает ошибку, а не незаметный выпуск неподписанного APK.

Перед следующим tag увеличивайте `version`/build number в `pubspec.yaml` и обновляйте версию в интерфейсе. Для ручного CI запуска debug: Actions → FLUS TEST APK → Run workflow.

### Обновление ядра

1. Зафиксируйте новый upstream commit и проверьте diff с текущим `vendor/`.
2. Сохраните FLUS-патчи, лицензии, go.mod и go.sum; не обновляйте всё вслепую.
3. Выполните тесты и `bash scripts/build-core.sh` — он заменит `libopenflux.so`.
4. Проверьте Start/Stop, повторный Start, занятый порт, фон, Wi-Fi/LTE и IP через реальный VPS.
5. Обновите версию, commit в README и выпустите новый **Pre-release**.

## Приёмка на телефоне

Сборка/статический анализ не доказывают работу Yandex-туннеля. Перед использованием проверить: Android 8/10/13/14/15 arm64, Start → SOCKS5 → Stop → Start, отказ уведомлений, фон/сон, занятый порт, падение/force-stop процесса, edit/public/невалидные ссылки, Wi-Fi/LTE (включая IPv6/NAT64), RX-PRO exception, внешний IP, DNS/IPv6/UDP leaks. Нужны ваш действующий документ и exit-node. Секретный URL в issue не прикладывать.

## Лицензия и дисклеймер

FLUS распространяется по GPL-3.0-or-later; полный текст — `LICENSE`. OpenFlux copyright и уведомления сохранены в `vendor/COPYRIGHT`, `vendor/LICENSE`, `vendor/NOTICE`. Исходники, необходимые для сборки этой версии, доступны в этом репозитории; зависимости перечислены в lock/sum-файлах.

**Только для образовательного использования. Тестируйте на своих устройствах и в сетях, где у вас есть разрешение. Без гарантий работоспособности или конфиденциальности транспорта.**
