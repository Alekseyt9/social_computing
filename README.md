# Adaptive Social Immersive Sim

Экспериментальный одиночный **social immersive sim** на Godot 4. Игрок — не
управляющий обществом, а обычный участник живого социального мира. Цели
достигаются через знакомства, доверие, информацию, репутацию, услуги и
организации.

Первый vertical slice строится вокруг задачи попасть на закрытую вечеринку
компании **Aurora**. У неё нет одного заранее заданного решения: игрок должен
исследовать связи между персонажами, договариваться, помогать им и находить
альтернативные социальные пути.

[![Три социальных пути к закрытой вечеринке Aurora](docs/diagrams/aurora-social-paths.svg)](docs/diagrams/aurora-social-paths.svg)

## Игровой цикл

Игрок не нажимает абстрактную кнопку убеждения. Он выясняет, почему человек не
готов помочь, меняет отношения или обстоятельства и пробует новый путь.

[![Игровой цикл Social Immersive Sim](docs/diagrams/gameplay-loop.svg)](docs/diagrams/gameplay-loop.svg)

## Основные принципы

- состояние мира и знания персонажей хранятся раздельно;
- решения NPC вычисляет детерминированная симуляция, а не LLM;
- **Social Renderer** превращает готовое структурированное решение в реплику;
- Groq отвечает только за форму текста и не может изменять состояние мира;
- детализация агентов должна адаптироваться от групп населения до активных NPC;
- симуляция запускается без интерфейса и воспроизводится по seed.

```text
World → Social Simulation → NPC Decision → Communicative Act
      → Social Renderer → LLM или шаблон → Реплика игроку
```

[![Архитектура Social Rendering](docs/diagrams/social-rendering-pipeline.svg)](docs/diagrams/social-rendering-pipeline.svg)

### Адаптивная детализация

По мере приближения к игроку и текущей ситуации агрегаты превращаются в
индивидуальных агентов. В обратную сторону детали сворачиваются без потери
важной истории и persistent identity.

[![Уровни адаптивной социальной симуляции](docs/diagrams/adaptive-simulation-levels.svg)](docs/diagrams/adaptive-simulation-levels.svg)

## Текущий прототип

Уже реализованы:

- детерминированное ядро `SimulationWorld`;
- игрок, 20 NPC, Office, Cafe и Apartment;
- модели людей, организаций, отношений, фактов, знаний и событий;
- разделение канонической истины и доступной игроку информации;
- сценарий Aurora и несколько потенциальных социальных маршрутов;
- изолированный Groq-клиент с безопасной загрузкой API-ключа;
- интерфейс walking skeleton и headless-тесты.

Ближайший milestone: социальные действия `AskAbout`, `AskFavor` и
`AskIntroduction`, Decision Engine, раскрытие причин решений NPC, fallback
renderer и карта известных игроку связей.

## Структура

```text
game/core/        детерминированная симуляция и модели мира
game/llm/         изолированный провайдер Groq
game/ui/          визуальный экран разговора и социального маршрута
game/tests/       headless и integration-тесты
docs/             план ближайших этапов
scripts/          локальный запуск с переменными окружения
```

Полное техническое задание: [adaptive_social_immersive_sim_codex_spec.md](adaptive_social_immersive_sim_codex_spec.md).

## Запуск

Требуется Godot 4.7+.

Самый простой способ запустить игру из PowerShell в корне проекта:

```powershell
.\scripts\run-godot.ps1
```

Открыть проект в редакторе:

```powershell
.\scripts\run-godot.ps1 -Editor
```

В редакторе нажмите **F6** для текущей сцены или **F5** для всего проекта.
Groq не обязателен: без API-ключа игра запускается с локальным шаблонным
renderer.

Прямой запуск без вспомогательного скрипта:

```powershell
godot --path ./game
godot --editor --path ./game
```

Проверка детерминированной симуляции:

```powershell
godot_console --headless --path ./game --script res://tests/headless_test.gd
```

## Groq API

Скопируйте пример конфигурации и добавьте собственный ключ только в локальный
`.env`:

```powershell
Copy-Item .env.example .env
.\scripts\run-godot.ps1 -Editor
```

```dotenv
GROQ_API_KEY=gsk_...
GROQ_MODEL=openai/gpt-oss-20b
```

Файл `.env` находится в `.gitignore`; настоящий API-ключ не должен попадать в
Git, логи или сообщения. Реальный integration-тест выполняется командой:

```powershell
godot --headless --path ./game --script res://tests/groq_integration_test.gd
```
