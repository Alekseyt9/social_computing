# Adaptive Social Immersive Sim

Первый технический walking skeleton на Godot 4 и GDScript.

## Структура

- `game/` — проект Godot 4.
- `game/core/` — независимое от сцен ядро симуляции на GDScript.
- `game/core/model/` — модели людей, отношений, фактов, знаний, мест, организаций и событий.
- `game/tests/` — headless smoke tests.
- `docs/first-steps.md` — ближайший план разработки.

## Сборка и проверка

```powershell
godot_console --headless --path ./game --script res://tests/headless_test.gd
```

Обычный запуск редактора:

```powershell
godot --editor --path ./game
```

Ядро симуляции остаётся полностью детерминированным. Groq подключён отдельным
renderer-клиентом и не имеет доступа к изменению состояния мира.

Сценарий создаёт игрока, 20 NPC и три места. Каноническая истина мира отделена
от знаний персонажей: игрок изначально видит только собственную связь с Анной.

## Groq API

1. Отзовите любой ключ, который был опубликован в чате или журнале.
2. Скопируйте `.env.example` в `.env` и вставьте новый ключ в
   `GROQ_API_KEY`. Файл `.env` исключён из репозитория.
3. Запустите проект через скрипт, который загрузит переменные только в процесс
   Godot:

```powershell
Copy-Item .env.example .env
.\scripts\run-godot.ps1 -Editor
```

Для разовой настройки без `.env` можно задать переменную в текущем терминале:

```powershell
$env:GROQ_API_KEY = "ваш_новый_ключ"
godot --editor --path ./game
```

Кнопка **«Проверить Groq API»** отправляет короткий тестовый запрос. По
умолчанию используется production-модель `openai/gpt-oss-20b`; её можно
переопределить переменной `GROQ_MODEL`.
