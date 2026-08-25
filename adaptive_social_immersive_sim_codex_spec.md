# ТЗ для Codex: Adaptive Social Immersive Sim

## 1. Концепция

Нужно создать прототип одиночной игры нового типа — **Social Immersive Sim**.

Игрок управляет одним человеком внутри большого динамического социального мира.

Игрок **не управляет городом или обществом сверху**. Он является обычным участником системы и достигает целей через:

- людей;
- знакомства;
- доверие;
- информацию;
- репутацию;
- услуги;
- организации;
- деньги;
- социальные роли;
- изменение обстоятельств.

Основная идея:

> Обычный immersive sim предлагает физическое пространство и спрашивает: «Как ты попадёшь внутрь здания?»

> Social Immersive Sim предлагает общество и спрашивает: «Как ты доберёшься до нужного человека или результата через людей?»

---

## 2. Главная техническая идея

Мир должен симулироваться **адаптивно**, аналогично adaptive particle simulation / level-of-detail simulation.

Нельзя подробно симулировать каждого жителя огромного города.

Использовать несколько уровней социальной детализации:

```text
Population aggregates
        ↓
Lightweight agents
        ↓
Persistent individuals
        ↓
Active detailed NPC
```

Чем важнее человек для игрока или текущей ситуации, тем подробнее его модель.

---

## 3. Новый термин: Social Rendering

Использовать понятие:

## Social Rendering / Социальный рендеринг

Определение:

> Social Rendering — преобразование внутреннего структурированного состояния социального агента в наблюдаемое человеком поведение.

Внутренняя симуляция определяет:

- что NPC знает;
- что он думает;
- чего хочет;
- чего боится;
- какие у него отношения;
- какое решение он принял;
- почему он его принял;
- какую часть причины он готов раскрыть.

Social Renderer превращает это в:

- человеческую реплику;
- сообщение;
- описание реакции;
- позже — голос, интонацию, жесты, мимику.

LLM **не должна определять игровую истину или решение NPC**.

Она только «рендерит» уже вычисленный социальный смысл.

Архитектура:

```text
WORLD
  ↓
SOCIAL SIMULATION
  ↓
NPC DECISION
  ↓
COMMUNICATIVE ACT
  ↓
SOCIAL RENDERER
  ↓
LLM
  ↓
PLAYER-VISIBLE SPEECH
```

---

## 4. Цель первого прототипа

Не пытаться сразу сделать город на миллион жителей.

Создать **играбельный vertical slice**, доказывающий основную механику.

Для первой версии:

```text
1 район
~1 000–10 000 виртуальных жителей
~100 lightweight individual agents
~20–50 persistent NPC
~5–15 NPC вокруг игрока в высокой детализации
```

Допускается первоначально использовать меньшие числа.

Но архитектура должна позволять позже масштабироваться до:

```text
100 000+
1 000 000+
```

агентов.

---

## 5. Игровой сценарий vertical slice

Игроку ставится цель:

> Попасть на закрытое мероприятие компании Aurora.

Никакого заранее заданного правильного решения нет.

В мире существуют:

- сотрудники Aurora;
- организатор мероприятия;
- охрана;
- журналисты;
- подрядчики;
- знакомые сотрудников;
- друзья;
- родственники;
- участники профессионального сообщества.

Игрок должен найти социальный путь.

Например:

```text
PLAYER
 ↓
Anna
 ↓
Sergey
 ↓
Maria
 ↓
event organizer
```

Но это только один потенциальный вариант.

Другие системные способы:

- познакомиться с сотрудником;
- попросить приглашение;
- устроиться временным работником;
- стать журналистом;
- помочь кому-то из гостей;
- купить приглашение;
- убедить охранника;
- получить рекомендацию;
- создать ситуацию, при которой организатор сам захочет встретиться с игроком.

---

## 6. Игровой цикл

Основной цикл:

```text
PLAYER HAS GOAL
      ↓
discover opportunity
      ↓
attempt action
      ↓
NPC evaluates request
      ↓
SUCCESS / FAILURE / NEGOTIATION
      ↓
player learns something
      ↓
changes circumstances
      ↓
tries another path
```

Отказ NPC должен быть частью gameplay.

Пример:

Игрок:

```text
Дай мне внутренний документ.
```

Внутренняя симуляция:

```text
trust(player) = 0.63

personal_risk = 0.91
fear_of_boss = 0.86
loyalty = 0.32

decision = REFUSE
primary_reason = PERSONAL_RISK
secondary_reason = FEAR_OF_BOSS
```

Social Renderer:

```text
— Ты с ума сошёл?
Если Виктор увидит, что я открывал этот файл,
меня уволят.
```

Игрок получает новую информацию:

```text
Victor exists
Victor monitors access
NPC fears losing job
```

Возникают новые пути решения.

---

## 7. Adaptive Social Simulation

### Level L3 — Population Aggregate

Большая социальная группа.

Например район:

```text
PopulationAggregate {
    id

    populationCount

    ageDistribution
    incomeDistribution
    employmentDistribution

    wealth
    stress
    happiness

    trustLevel
    crimeLevel

    politicalTension
    migrationRate

    groupComposition
}
```

Один aggregate может представлять:

```text
100
1 000
10 000
100 000
```

людей.

---

## 8. Level L2 — Lightweight Agent

Отдельный человек, но без полной индивидуальной истории.

```text
LightAgent {
    id

    age
    sex

    homeId
    workplaceId
    position

    income
    money

    stress
    mood

    sociability
    conformity
    empathy
    ambition
    aggression
    riskTolerance

    householdId
    organizationIds[]
}
```

LightAgent дешёвый.

Он может:

- работать;
- тратить деньги;
- перемещаться;
- вступать в локальные взаимодействия;
- менять настроение;
- менять социальные группы;
- мигрировать;
- менять работу.

---

## 9. Level L1 — Persistent NPC

Если человек становится важным, он превращается в persistent entity.

Причины promotion:

```text
player talked to NPC
player remembers NPC
NPC remembers player
NPC involved in important event
NPC connected to important NPC
NPC carries important knowledge
```

PersistentNPC:

```text
PersistentNPC {
    id

    identity
    personality

    currentState

    relationships[]
    knownFacts[]
    goals[]
    obligations[]

    household
    employment

    importantMemories[]
    historyAnchors[]
}
```

Persistent NPC больше никогда не должен полностью исчезать в статистике.

Его background simulation можно упрощать.

---

## 10. Level L0 — Active NPC

NPC находится непосредственно рядом с игроком или участвует в важном событии.

Дополнительно считать:

```text
currentGoal
currentEmotion
attention
conversationState

immediateNeeds
currentRiskEvaluation
socialContext
```

Только Active NPC участвует в дорогом Social Rendering.

---

## 11. Adaptive refinement

Переход:

```text
Aggregate
   ↓
LightAgents
   ↓
PersistentNPC
   ↓
ActiveNPC
```

Детализация определяется не только расстоянием.

Использовать:

```text
importanceScore =
    playerDistance
    + socialDistanceToPlayer
    + eventImportance
    + knowledgeImportance
    + relationshipImportance
```

Пример:

NPC находится далеко от игрока, но является:

```text
boss of player's friend
```

Он может оставаться persistent.

---

## 12. Coarsening

При удалении игрока ActiveNPC превращается обратно в PersistentNPC.

Для background simulation PersistentNPC можно обновлять значительно реже.

Например:

```text
Active NPC:
every second

Persistent NPC:
every game hour

Light Agent:
every game day

Population Aggregate:
large timestep / event-driven
```

---

## 13. Lazy History

Не нужно симулировать все события каждого persistent NPC каждую минуту.

Хранить только **history anchors**.

Пример:

```text
Day 12:
job = supermarket
partner = Anna
money = 1200

Day 48:
job = courier
partner = none
money = 1700
```

Если игрок спрашивает:

> Что у тебя произошло за этот месяц?

система может восстановить промежуточную историю.

Но история должна удовлетворять ограничениям мира.

Например:

```text
supermarket closed Day 21

→ lost job
→ money pressure increased
→ relationship conflict
→ breakup
→ job search
→ courier job
```

После того как reconstructed event стал известен игроку, он превращается в canonical event.

---

## 14. World Graph

Логически мир представить как heterogeneous graph.

Типы nodes:

```text
Person
Organization
Place
Household
Group
Fact
Event
Item
```

Edges:

```text
knows
friend_of
family_of

works_for
member_of

lives_at
visits

trusts
likes
dislikes
fears

owes
depends_on

owns
controls

knows_fact
believes_fact

witnessed
heard_from
```

Не использовать глобальную dense matrix.

---

## 15. Физическое хранение

Logical Graph != Graph Database.

Для производительности использовать специализированные структуры:

```text
people[]
relationships[]
organizationMembership[]
locationOccupants[]
facts[]
knowledgeEdges[]
events[]
```

Для больших графов:

```text
CSR / adjacency arrays
```

При необходимости использовать ECS.

Граф является **логической gameplay abstraction**, а не обязательным storage format.

---

## 16. Relationship model

Не использовать один параметр:

```text
friendship = 73
```

Relationship:

```text
Relationship {
    familiarity
    trust
    affection
    respect
    fear
    resentment
    attraction
    obligation
}
```

Например человек может:

```text
respect = high
affection = low
fear = medium
```

---

## 17. Personality model

Не создавать сотни traits.

Для первого прототипа:

```text
Personality {
    sociability
    empathy
    honesty
    conformity
    ambition

    aggression
    impulsivity

    loyalty
    curiosity
    riskTolerance
}
```

Все значения:

```text
0..1
```

---

## 18. Dynamic state

```text
DynamicState {
    mood
    stress
    fear
    anger

    loneliness

    moneyPressure
    statusNeed
    belongingNeed
}
```

---

## 19. Knowledge System

Строго разделить:

```text
TRUTH
OBSERVATION
KNOWLEDGE
BELIEF
```

Пример.

Truth:

```text
John stole file.
```

Maria:

```text
Maria saw John leaving the office.
```

Sergey:

```text
Sergey heard from Maria
that John was near the office.
```

Alex:

```text
Alex believes John stole the file.
confidence = 0.65
```

---

## 20. Fact

```text
Fact {
    id

    subject
    predicate
    object

    timestamp

    importance
    secrecy

    truthStatus
}
```

Пример:

```text
subject = CompanyA
predicate = layoffs
object = 300
```

---

## 21. Knowledge Edge

```text
Knowledge {
    personId
    factId

    confidence

    sourceId

    learnedAt

    disclosureThreshold
}
```

Один Fact не копировать для каждого NPC.

---

## 22. Belief

NPC может верить в ложную информацию.

Например:

```text
Fact:
Company NOT bankrupt

Belief:
Ivan believes Company bankrupt
confidence = 0.85
```

Поведение Ivan должно исходить из **belief**, а не из objective truth.

---

## 23. Gossip propagation

Слухи должны распространяться через социальный граф.

Использовать вероятностную модель:

```text
P(share) =
    novelty
    * emotionality
    * relationship
    * sociability
    * perceivedImportance
```

При передаче:

```text
confidence *= transmissionReliability
```

Допускается небольшое изменение semantic interpretation.

Не разрешать LLM произвольно изменять facts.

---

## 24. Large-scale information propagation

При распространении информации на очень большое количество NPC не хранить бесконечное число KnowledgeEdge.

Использовать адаптивное представление.

Например:

```text
< 1 000 people
individual propagation

1 000–100 000
group propagation

> 100 000
information field / aggregate distribution
```

---

## 25. Social Fields

Некоторые социальные явления считать как поля.

Для района:

```text
fear
wealth
crime
employment
trust
socialTension
informationExposure
```

Agent:

```text
reads field
↓
changes internal state
↓
acts
↓
contributes back to field
```

Получается:

```text
Agents ↔ Social Fields
```

Подход аналогичен particle-field simulation.

---

## 26. Social Actions

Не создавать сотни scripted interactions.

Создать ограниченный набор универсальных параметризованных operators.

Начальный список:

```text
Talk
Ask
AskAbout

Tell
RevealFact
HideFact
Lie

AskFavor
OfferFavor

AskIntroduction
Introduce

OfferHelp
RequestHelp

Give
Borrow
Lend

Buy
Sell
Trade

Invite

Persuade

Threaten
Blackmail

Apologize
Support

Flirt

Observe
Follow
Investigate

ApplyForJob
QuitJob

JoinOrganization
LeaveOrganization

EnterPlace
```

---

## 27. Action representation

Например:

```text
SocialAction {
    type

    actor
    target

    subject
    object

    context
}
```

Пример:

```text
type = AskIntroduction

actor = Player
target = Ivan

subject = Maria
```

---

## 28. Preconditions

Каждый operator имеет Preconditions.

Например:

```text
AskIntroduction(Player, Ivan, Maria)
```

возможен, если:

```text
Player knows Ivan

Ivan knows Maria
```

Но это только возможность совершить request.

NPC может отказаться.

---

## 29. NPC Decision Engine

LLM не использовать для decision making.

Использовать utility evaluation.

Пример:

```text
helpUtility =
      trust * 1.3
    + affection
    + obligation * 1.5
    + expectedBenefit
    - personalCost
    - risk * 1.5
    - moralResistance
```

Результат:

```text
ACCEPT
REFUSE
NEGOTIATE
DELAY
ASK_RETURN_FAVOR
AVOID
LIE
```

---

## 30. Не использовать жёсткие success percentages

Игрок не должен видеть:

```text
SUCCESS 74%
```

Игрок получает качественные сигналы:

```text
Он явно нервничает.

Кажется, он тебе доверяет.

Тема начальника вызывает у него напряжение.
```

---

## 31. Decision explanation

DecisionEngine обязан вернуть структурированную причину.

Пример:

```json
{
  "decision": "REFUSE",
  "primaryReason": {
    "type": "PERSONAL_RISK",
    "value": 0.91
  },
  "secondaryReasons": [
    {
      "type": "FEAR_PERSON",
      "entityId": "victor",
      "value": 0.84
    }
  ]
}
```

---

## 32. Disclosure

Решение и объяснение — разные вещи.

NPC может отказаться из-за Victor, но не сказать об этом.

Рассчитать:

```text
DisclosureScore =
    trust
    + honesty
    + intimacy
    - secrecy
    - fear
```

Пример:

### Low disclosure

```text
Нет.
```

### Medium

```text
Мне за такое сильно прилетит.
```

### High

```text
Виктор смотрит логи.
Если увидит мой аккаунт — меня уволят.
```

---

## 33. Communicative Act

Перед SocialRenderer сформировать строго структурированный объект.

```json
{
  "act": "REFUSE_REQUEST",

  "reason": {
    "type": "JOB_RISK"
  },

  "revealedFacts": [
    {
      "type": "BOSS_MONITORS_ACCESS",
      "person": "Victor"
    }
  ],

  "emotion": {
    "fear": 0.82,
    "irritation": 0.31
  },

  "relationship": {
    "familiarity": 0.71,
    "trust": 0.61
  },

  "speechStyle": {
    "directness": 0.8,
    "politeness": 0.3,
    "sarcasm": 0.2,
    "verbosity": 0.3
  }
}
```

---

## 34. SocialRenderer

Создать интерфейс:

```text
SocialRenderer
```

Метод концептуально:

```text
Render(
    CharacterIdentity,
    CommunicativeAct,
    ConversationContext
) -> RenderedSocialResponse
```

---

## 35. LLM Provider

Не связывать игру с одной моделью.

Создать интерфейс:

```text
LanguageModelProvider
```

Поддержать:

```text
OpenAI-compatible HTTP API
```

чтобы можно было использовать:

- бесплатный API;
- облачный inference;
- OpenRouter-подобный сервис;
- локальный llama.cpp server;
- Ollama;
- vLLM;
- собственный backend.

Конкретный provider должен задаваться конфигом.

---

## 36. Безопасность состояния мира при LLM

LLM запрещено создавать новые canonical facts.

Например модель не имеет права самостоятельно сказать:

```text
Я уже украл этот документ вчера.
```

если такого события нет.

В prompt явно передавать:

```text
You may only express the information provided below.

Do not invent:
people
events
relationships
places
facts
past events.
```

---

## 37. Semantic validation

После ответа LLM желательно выполнить лёгкую проверку.

Минимальная версия:

проверить:

- не появились неизвестные proper nouns;
- были выражены необходимые semantic facts.

В будущем возможен второй маленький LLM verifier.

---

## 38. Fallback renderer

Если API:

- недоступен;
- медленный;
- вернул ошибку;

игра должна продолжать работать.

Сделать template fallback.

Например:

```text
REFUSE + JOB_RISK + Victor

→

«Нет. Если Виктор узнает, у меня будут проблемы.»
```

LLM улучшает naturalness, но не является критической dependency gameplay.

---

## 39. Conversation state

Conversation:

```text
Conversation {
    participants[]

    activeTopics[]

    recentlyMentionedFacts[]

    emotionalTone

    previousCommunicativeActs[]
}
```

Не передавать LLM огромную историю мира.

Передавать только:

```text
current NPC
current player
relevant known facts
current request
recent conversation
communicative act
```

---

## 40. Player knowledge

Игрок тоже должен иметь Knowledge Graph.

Игрок не получает omniscient information.

Например реальность:

```text
Maria knows Victor.
```

Но пока игрок этого не знает, UI не показывает связь.

После разговора:

```text
PlayerKnowledge:
Maria knows Victor
```

---

## 41. Discovery as gameplay

Социальный граф раскрывается постепенно.

Игрок видит только известные связи.

Например:

```text
Anna
 ↓
? someone at Aurora
```

После разговора:

```text
Anna
 ↓
Sergey
 ↓
Aurora
```

Позже:

```text
Anna
 ↓
Sergey
 ↓
Maria
 ↓
Event Organizer
```

Социальный граф является аналогом карты мира.

---

## 42. Player UI

Для vertical slice нужен простой UI.

Основной экран:

```text
current location

nearby NPC

conversation

known people

known facts

current goals
```

Дополнительно:

### Social Map

Отображает только известную игроку часть графа.

Nodes:

```text
people
organizations
places
```

Edges:

```text
knows
works_for
friend
family
```

Не показывать скрытые связи.

---

## 43. Interaction UI

При выборе NPC выводить доступные categories:

```text
Talk

Ask about...
Ask favor...
Ask introduction...
Tell...
Offer...
```

Не выводить тысячи действий.

Использовать context filtering.

---

## 44. Contextual interaction generation

Для текущей ситуации собрать:

```text
Player
Target NPC

PlayerKnowledge
TargetKnowledge

relationships

location

currentGoals

recentEvents
```

На основе этого вывести Top-N meaningful actions.

Например максимум:

```text
5–10
```

релевантных interaction options.

---

## 45. Не делать полный global solver

Не пытаться постоянно вычислять все возможные действия во всём мире.

Это приведёт к combinatorial explosion.

Использовать:

```text
local reasoning
bounded graph queries
event-driven simulation
```

---

## 46. Goal Solver

Нужен внутренний planner, но он НЕ должен играть вместо игрока.

Его задачи:

1. проверять, существуют ли пути достижения цели;
2. помогать procedural generation;
3. находить потенциальные opportunities;
4. проверять, что цель не стала невозможной.

---

## 47. Hierarchical Planner

Не искать сразу:

```text
Player → среди 1 000 000 NPC → target
```

Использовать hierarchy.

Для цели:

```text
GET_INVITED(Event)
```

сначала strategies:

```text
PERSONAL_INVITATION
EMPLOYMENT
MEDIA_ACCESS
SERVICE_PROVIDER
SOCIAL_CONNECTION
```

Например выбран:

```text
SOCIAL_CONNECTION
```

только после этого искать social graph.

---

## 48. Bounded Search

Использовать:

```text
maxDepth

beamWidth

topK
```

Например:

```text
maxDepth = 5
beamWidth = 20
topK = 10
```

Planner должен использовать heuristic relevance.

---

## 49. Не показывать planner path игроку

Если solver нашёл:

```text
Player
→ Anna
→ Sergey
→ Maria
→ Event
```

не показывать:

```text
QUEST SOLUTION FOUND
```

Игрок должен открыть путь через gameplay.

Можно лишь генерировать естественные hints.

---

## 50. Social propagation

Любое важное действие создаёт Event.

```text
Event {
    actors[]
    targets[]

    location

    importance

    emotionalIntensity

    secrecy

    affectedFacts[]
}
```

Event распространяет последствия локально.

---

## 51. Propagation budget

Чтобы избежать combinatorial explosion, каждое событие получает propagation energy.

Например:

```text
importance = 0.8
```

Передача:

```text
A → B

0.8 * relationStrength
```

Далее:

```text
B → C

previousStrength
* interest
* transmissionProbability
```

Если:

```text
strength < threshold
```

прекратить распространение.

---

## 52. Structural events

Не описывать социальную жизнь тысячами IF.

Большую часть состояния обновлять численно.

Rules использовать только для structural transitions:

```text
job_changed
relationship_started
relationship_ended
moved_home
joined_group
left_group
became_friend
became_enemy
company_closed
crime_committed
```

---

## 53. Numerical social dynamics

Например:

```text
trust += positiveInteraction * empathy

stress += financialPressure

relationship -= betrayalImpact
```

Многие социальные явления должны быть непрерывными, а не rule-based.

---

## 54. Event-driven simulation

Не обновлять каждого NPC каждый frame.

Использовать разные частоты.

Пример:

```text
movement:
seconds

active social state:
seconds

work activity:
game hours

finances:
game day

job search:
days

population dynamics:
weeks
```

---

## 55. Deterministic randomness

Использовать seeded PRNG.

Необходимо для:

- воспроизводимости;
- debugging;
- тестов;
- replay.

При одинаковом seed и одинаковых действиях игрока simulation должна давать одинаковый результат, если внешняя LLM не влияет на game state.

---

## 56. Очень важное правило LLM

LLM output никогда напрямую не изменяет simulation.

Нельзя:

```text
LLM:
«Я согласен.»

→ game sets agreement=true
```

Правильно:

```text
DecisionEngine:
ACCEPT

→ CommunicativeAct

→ LLM:
«Ладно, я помогу.»
```

Simulation является source of truth.

---

## 57. Performance architecture

Для массовой части использовать data-oriented design.

Предпочтительно:

```text
Structure of Arrays
```

вместо тяжёлых object graphs.

Например:

```text
money[]
stress[]
homeId[]
workplaceId[]
personality[]
```

---

## 58. GPU-ready architecture

Не обязательно делать GPU compute в первом milestone.

Но массовые обновления должны проектироваться так, чтобы позже можно было перенести их на:

```text
Compute Shaders
CUDA
DirectCompute
Vulkan Compute
```

Не размещать критическую bulk simulation в архитектуре, которая требует сложных pointer-rich objects.

---

## 59. Spatial partitioning

Для физических контактов использовать:

```text
spatial grid
spatial hash
```

Agent взаимодействует только с людьми:

```text
same cell
neighbor cells
same workplace
same household
same scheduled activity
```

---

## 60. Social graph interactions

Для non-spatial interactions использовать sparse social graph.

Например:

```text
family
friends
coworkers
weak ties
online contacts
```

Agent не взаимодействует с каждым жителем города.

---

## 61. Массовые взаимодействия

Пример одного игрового дня:

```text
1 000 000 agents

average meaningful contacts = 10

≈10M potential social contacts
```

Вместо:

```text
1M × 1M
```

Никаких all-pairs calculations.

---

## 62. Development stack

Выбрать простой стек, удобный для Codex и прототипирования.

Рекомендуемый вариант:

```text
Godot 4
C#
```

или:

```text
Godot 4
GDScript
```

Если Codex считает другой стек более подходящим, разрешается обоснованное изменение.

Приоритет:

1. скорость разработки;
2. читаемость архитектуры;
3. возможность тестировать simulation отдельно от rendering;
4. дальнейшая GPU compute integration.

Simulation core желательно отделить от engine-specific UI.

---

## 63. Headless simulation

Обязательно создать возможность запускать simulation без игры.

Например:

```text
simulate 100 days
```

и получить:

```text
population
employment
relationship changes
information spread
events
```

Это нужно для автоматических тестов.

---

## 64. Debug inspector

Создать dev-only окно для выбранного NPC.

Показывать:

```text
identity

personality

dynamic state

relationships

knowledge

beliefs

goals

current decision

decision utility components

recent events

simulation LOD
```

Игроку эти числа не показывать.

---

## 65. Social Renderer Debug

Отдельно отображать:

```text
Decision

CommunicativeAct

Prompt sent to LLM

Raw LLM output

Final sanitized output
```

для отладки.

---

## 66. Первый milestone

Сделать самую маленькую рабочую версию.

### World

```text
20 NPC
3 places

Office
Cafe
Apartment
```

### Organizations

```text
Aurora
Cafe
```

### Goal

```text
Get invitation to Aurora party
```

### Required systems

```text
Person
Relationship
Knowledge
Fact

AskAbout
AskFavor
AskIntroduction

DecisionEngine

CommunicativeAct

SocialRenderer

LLM API

Social Graph UI
```

---

## 67. Первый системный сценарий

Создать мир:

```text
Player knows Anna.

Anna knows Sergey.

Sergey works for Aurora.

Sergey knows Maria.

Maria organizes Aurora party.
```

Игрок знает только:

```text
Anna
```

Игрок должен через разговор самостоятельно раскрыть путь.

---

## 68. Failure scenario

Anna не должна автоматически знакомить игрока с Sergey.

Например:

```text
trust = 0.3

→ REFUSE
```

Игрок может:

```text
help Anna
increase trust
```

или найти другой путь.

---

## 69. Dynamic obstacle

Sergey знает Maria, но поссорился с ней.

```text
relationship:
resentment = 0.8
```

Он отвечает:

```text
Мы с Марией сейчас не разговариваем.
```

Игрок получает новый social problem.

---

## 70. Emergent alternative

Добавить другого NPC:

```text
Daniel
journalist
```

Он тоже может попасть на мероприятие.

Игрок потенциально может построить совсем другой путь.

Цель должна иметь минимум 3 системных решения.

---

## 71. Acceptance Criteria Milestone 1

Прототип считается успешным, если:

1. NPC имеют persistent identity.
2. NPC имеют relationships.
3. NPC обладают разным knowledge.
4. Игрок не видит неизвестные связи.
5. NPC способны отказать по конкретной simulated причине.
6. Причина может быть частично раскрыта.
7. LLM превращает structured reason в естественную реплику.
8. LLM не определяет решение NPC.
9. Один goal имеет несколько социальных путей решения.
10. Изменение отношений открывает новые действия.
11. Мир продолжает работать без LLM через fallback renderer.
12. Simulation можно запустить headless.
13. Все ключевые действия логируются.

---

## 72. Milestone 2 — Larger social simulation

После стабильного vertical slice:

```text
1 000+ lightweight agents
```

Добавить:

- households;
- workplaces;
- schedules;
- local contacts;
- job changes;
- money;
- social groups;
- basic gossip propagation.

---

## 73. Milestone 3 — Adaptive simulation

Добавить:

```text
Aggregate
↔ LightAgent
↔ PersistentNPC
```

Проверить conservation constraints.

Например:

```text
Aggregate:

1000 people
100 unemployed

Refine:

1000 agents
~100 unemployed
```

Coarsening должен возвращать корректную статистику.

---

## 74. Milestone 4 — Social fields

Добавить:

```text
district wealth
fear
crime
employment
social tension
```

Проверить feedback loops:

```text
unemployment ↑
→ stress ↑
→ spending ↓
→ businesses suffer
→ unemployment ↑
```

---

## 75. Milestone 5 — Lazy histories

Persistent NPC могут находиться вне detailed simulation недели.

При следующем появлении:

```text
background events
```

восстанавливаются согласованно.

---

## 76. Milestone 6 — GPU simulation

Только после работающей CPU simulation.

Перенести массовые операции:

```text
light agent state updates
spatial neighborhood
social fields
aggregate calculations
```

на compute shaders/GPU.

Persistent NPC reasoning можно оставить CPU-side.

---

## 77. Не делать на первом этапе

Не реализовывать:

- полноценный 3D-город;
- сложный combat;
- транспортную симуляцию;
- миллионы detailed NPC;
- полноценную экономику страны;
- голосовой синтез;
- сложную facial animation;
- полностью LLM-driven agents;
- генерируемые LLM квесты.

Сначала доказать social gameplay.

---

## 78. Кодовая архитектура

Разделить модули:

```text
/core
    SimulationWorld

/agents
    LightAgent
    PersistentNPC
    ActiveNPC

/social
    RelationshipSystem
    SocialActionSystem
    DecisionEngine
    SocialPropagation

/knowledge
    FactStore
    KnowledgeGraph
    BeliefSystem

/history
    EventStore
    HistoryReconstruction

/adaptive
    RefinementSystem
    CoarseningSystem

/planner
    GoalPlanner
    SocialGraphSearch

/rendering/social
    CommunicativeAct
    SocialRenderer

/llm
    LanguageModelProvider
    OpenAICompatibleProvider
    TemplateProvider

/ui
    ConversationUI
    SocialMap
    DebugInspector
```

Конкретные названия разрешается адаптировать под выбранный язык.

---

## 79. Тестирование

Обязательно unit tests для:

```text
relationship changes

decision utility

knowledge propagation

belief confidence

action preconditions

disclosure

planner reachability

aggregate refinement

coarsening

persistent identity
```

---

## 80. Симуляционные тесты

Добавить сценарии вида:

```text
Run 1000 simulated days
```

Проверять:

- отсутствие NaN;
- отсутствие invalid references;
- population consistency;
- отсутствие бесконечных propagation loops;
- ограниченный размер event queues;
- отсутствие exponential memory growth.

---

## 81. Метрики

Headless simulator должен выводить:

```text
agent count

persistent NPC count

relationship count

fact count

knowledge edge count

events per tick

average interaction count

planner search nodes

simulation time per tick

LLM calls

LLM latency

LLM failures
```

---

## 82. Event log

Все важные социальные изменения сохранять как structured events.

Например:

```json
{
  "type": "RELATIONSHIP_CHANGED",
  "actor": 153,
  "target": 821,
  "cause": 88419,
  "delta": {
    "trust": -0.2
  }
}
```

Это пригодится для:

- debugging;
- history reconstruction;
- explanations;
- replays.

---

## 83. Explainability

Для каждого важного NPC decision должна существовать возможность спросить в debug mode:

```text
WHY?
```

Пример:

```text
REFUSE REQUEST

+ trust           +0.62
+ obligation      +0.10

- personal risk   -0.91
- fear Victor     -0.72

TOTAL              -0.91

Decision:
REFUSE
```

---

## 84. Главный дизайн-принцип

Игрок должен ощущать:

> «Я не нажимаю кнопку убеждения. Я понимаю, почему этот человек не хочет мне помогать, и меняю обстоятельства.»

---

## 85. Главный технический принцип

Не моделировать социальную жизнь как огромное количество жёстко прописанных правил.

Использовать комбинацию:

```text
continuous states
+
utility decisions
+
sparse graph
+
events
+
structural rules
+
adaptive aggregation
+
bounded planning
+
social rendering
```

---

## 86. Главный принцип Social Rendering

Simulation отвечает:

```text
WHAT HAPPENED?
WHAT NPC DECIDED?
WHY?
WHAT NPC KNOWS?
WHAT NPC WILL REVEAL?
```

LLM отвечает только:

```text
HOW WOULD THIS PERSON EXPRESS IT?
```

---

## 87. Ожидаемый конечный эффект

Игрок сталкивается с человеком.

Для игрока это выглядит просто:

```text
— Поможешь мне достать документ?

— Ты серьёзно?
Виктор отслеживает каждый доступ.
Если он увидит мой логин — я вылечу отсюда.
```

Но внутри игры за этой фразой находятся:

```text
world state
        ↓
organization hierarchy
        ↓
employment
        ↓
relationship graph
        ↓
knowledge graph
        ↓
risk evaluation
        ↓
personality
        ↓
decision
        ↓
disclosure
        ↓
communicative act
        ↓
Social Renderer
        ↓
LLM
        ↓
human speech
```

Именно этот эффект является центральной целью проекта.

---

## 88. Что Codex должен сделать первым

Не начинать с реализации всей архитектуры.

Сначала:

1. создать структуру проекта;
2. реализовать минимальные data models;
3. сделать deterministic simulation core;
4. реализовать Relationship + Knowledge;
5. реализовать три действия:
   - AskAbout;
   - AskFavor;
   - AskIntroduction;
6. реализовать DecisionEngine;
7. реализовать CommunicativeAct;
8. реализовать template SocialRenderer;
9. добавить OpenAI-compatible LLM provider;
10. создать простой UI разговора;
11. создать Social Map;
12. сделать сценарий Aurora Party;
13. добавить headless tests;
14. только после работающего vertical slice расширять масштаб.

При каждом этапе поддерживать возможность запуска без внешнего LLM API.

---

## 89. Критерий успеха всей концепции

Прототип должен создать ситуацию, в которой игрок самостоятельно обнаруживает социальный маршрут, которого ему явно не показывали.

Например:

```text
Мне нужен доступ к мероприятию.

↓ узнать

Анна знает Сергея.

↓ проблема

Анна недостаточно мне доверяет.

↓ действие

Помочь Анне с существующей проблемой.

↓ изменение мира

Trust увеличивается.

↓ действие

Анна знакомит с Сергеем.

↓ новая проблема

Сергей поссорился с организатором.

↓ исследование

Найти другого общего знакомого.

↓ новая возможность

Журналист Daniel.

↓ альтернативный маршрут

Получить доступ через прессу.
```

Если такая цепочка возникает из состояния мира и универсальных систем, а не из заранее прописанного quest script, архитектура работает.
