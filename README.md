# LongDarks

Мобильная (Android) низкополигональная игра-выживание и градостроительный симулятор
с видом сверху. Движок: Godot 4 (GDScript), рендерер Mobile. Поддерживаются обе
ориентации экрана (портрет и ландшафт).

Сейчас в репозитории только каркас проекта, геймплея нет.

## Структура

- `src/core` — общие базовые системы
- `src/sim` — симуляция (выживание, экономика, постройки)
- `src/ui` — интерфейс
- `src/world` — мир, карта, генерация
- `scenes/` — сцены (`scenes/main.tscn` — главная)
- `assets/` — ассеты
- `tests/` — тесты

## Запуск тестов

Нужен Godot 4.7.x (проект проверен на 4.7.2). При первом запуске (или после добавления
`class_name` скриптов) нужно собрать кэш классов:

```
godot --headless --path . --import
godot --headless --path . -s tests/run_tests.gd
```

Раннер находит `tests/**/test_*.gd`, запускает методы `test_*` и завершается с кодом 1,
если есть упавшие тесты. Тесты наследуются от `res://tests/test_case.gd` (`assert_true`,
`assert_eq`, `assert_almost_eq`, ...).

## Сборка APK

Настроен пресет `Android` (`export_presets.cfg`, пакет `com.longdarks.game`, arm64).
Нужны шаблоны экспорта и Android SDK; debug keystore задаётся в настройках редактора,
секреты в репозиторий не коммитятся. Пример CI-сборки — `.github/workflows/ci.yml`.

### Debug keystore и versionCode

`android/debug.keystore` — общий debug-ключ (alias `androiddebugkey`, пароли `android`),
закоммичен намеренно: CI подписывает им каждую сборку, поэтому новый APK ставится поверх
старого. Это публичный debug-ключ, НЕ для релиза в Google Play; релизный ключ позже
будет храниться в GitHub Secrets. В CI `version/code` в `export_presets.cfg` подставляется
из `GITHUB_RUN_NUMBER` (только внутри job, в репозитории остаётся 1).
