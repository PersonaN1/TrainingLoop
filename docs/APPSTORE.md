# App Store: страница приложения

Тексты для App Store Connect на двух языках, как у SetLoop. Лимиты Apple: название и подзаголовок — 30 символов, промотекст — 170, ключевые слова — 100 байт (кириллица — 2 байта на букву, через запятую без пробелов, без слов из названия и подзаголовка), описание — 4000. Все тексты в лимитах.

## Общее

| Поле | Значение |
|---|---|
| Основная категория | Health & Fitness / Здоровье и фитнес |
| Дополнительная категория | Sports / Спорт |
| Возрастной рейтинг | 4+ (все ответы анкеты — «нет», см. ниже) |
| Цена | Бесплатно |
| Приватность | Data Not Collected (D14) |
| Privacy Policy URL | https://personan1.github.io/TrainingLoop/privacy/ |
| Support URL | https://personan1.github.io/TrainingLoop/support/ |
| Marketing URL | https://personan1.github.io/TrainingLoop/ |
| Copyright | 2026 Aleksandr Vasilev (написание — как в аккаунте разработчика) |

Ссылку на донаты в тексты App Store не ставим (App Review 3.1.1): она только в README, на главной сайта и в канале.

### Анкета возрастного рейтинга

Во всех разделах — «нет» / «None»: насилия, страшного, взрослых тем, азартных игр, алкоголя и табака нет; нет неограниченного доступа в интернет, общения пользователей, пользовательского контента, рекламы, покупок, родительского контроля и ИИ-чата. Вопрос о медицине и здоровье (Medical or Wellness Topics) — тоже «нет»: приложение записывает тренировки пользователя и не даёт медицинских, диетических или тренерских советов. Расчётный 1ПМ — справочная формула, а не рекомендация.

### Приватность (App Privacy)

«Do you or your third-party partners collect data from this app?» — **No, we do not collect data from this app.** Итог на странице: **Data Not Collected**.

Основание: нет аккаунтов, аналитики, рекламы, сторонних SDK и сетевых запросов; тренировки, шаблоны и настройки хранятся только на устройстве (SwiftData). Уведомление «Отдых окончен» — локальное, с устройства не уходит. Манифест `TrainingLoop/PrivacyInfo.xcprivacy` объявляет только UserDefaults (CA92.1) для настроек.

## Русский

**Название:** TrainingLoop

**Подзаголовок:** Дневник силовых тренировок

**Промотекст** (можно менять без ревью):

Составляйте шаблоны или импровизируйте на ходу. Добавляйте забытые тренировки, следите за прогрессом и делитесь тренировками. Бесплатно, без подписок и рекламы.

**Ключевые слова:**

зал,качалка,штанга,подходы,повторы,рекорды,прогресс,gym

**Описание:**

TrainingLoop — дневник силовых тренировок для iPhone. Составляйте шаблоны тренировок или импровизируйте на ходу. В зале просто отмечайте подходы. Сохраняйте выполненные тренировки и добавляйте забытые. Следите за прогрессом тренировок и каждого упражнения по графикам и рекордам, обновляйте шаблоны и делитесь тренировками с кем угодно.

ШАБЛОНЫ
• Упражнения в нужном порядке, у каждого — свои подходы: повторы или время, вес и отдых.
• Суперсеты: соседние упражнения выполняются по кругу.
• Пирамиды и разминочные подходы задаются отдельными строками.
• Можно тренироваться и без плана — в свободной тренировке.
• Для начала есть три готовых примера.

ВО ВРЕМЯ ТРЕНИРОВКИ
• Рядом с каждым подходом — результат прошлого раза, поля заполняются сами.
• Отметили подход — начался отдых. Сигналы звуком, голосом и вибрацией.
• Отдых и текущий подход на экране блокировки и в Dynamic Island.
• Новый рекорд отмечается 🏆 прямо у подхода.

ИСТОРИЯ И ПРОГРЕСС
• Личные рекорды: максимальный вес, лучший вес на 1, 3, 5, 8 и 10 повторов, повторы, время и тоннаж.
• График по каждому упражнению: лучший вес, тоннаж, повторы или время — за неделю, месяц, три месяца, год или всё время.
• Сводка за неделю, месяц и год: тренировки, время, тоннаж, подходы по группам мышц и серия недель.
• Забыли записать тренировку — добавьте её задним числом или исправьте прошлую: рекорды и графики пересчитаются.
• Шаблон, тренировку или все тренировки за период можно отправить текстом — например, тренеру.

УПРАЖНЕНИЯ И НАСТРОЙКИ
• 53 встроенных упражнения на русском и английском, а также ваши собственные.
• Поиск и фильтры по группе мышц и оборудованию.
• Килограммы или фунты, светлая и тёмная тема.

Бесплатно и без ограничений: все функции доступны сразу — без подписок, платных дополнений, рекламы и регистрации. Тренировки хранятся только на вашем iPhone.

Вопросы и предложения: t.me/setnewloop

## English

**Name:** TrainingLoop

**Subtitle:** Strength Workout Log

**Promotional text:**

Plan templates or improvise as you go. Add workouts you forgot to log, follow your progress and share your workouts. Free, no subscriptions, no ads.

**Keywords:**

gym,tracker,lifting,weightlifting,bodybuilding,sets,reps,progress,records,planner,fitness,exercise

**Description:**

TrainingLoop is a strength training log for iPhone. Plan workout templates or improvise as you go. At the gym, simply tick off your sets. Save finished workouts and add the ones you forgot to log. Follow the progress of your workouts and of every exercise with charts and records, update your templates and share your workouts with anyone.

TEMPLATES
• Exercises in the order you want, each with its own sets: reps or time, weight and rest.
• Supersets: neighbouring exercises are done in rounds.
• Pyramids and warm-up sets are simply separate rows.
• Or train without a plan in a free workout.
• Three ready-made examples to get you started.

DURING THE WORKOUT
• Next to every set you see last time's result; the fields fill in by themselves.
• Tick off a set and the rest begins, with sounds, voice cues and vibration.
• Rest and the current set on the Lock Screen and in the Dynamic Island.
• A new record is marked 🏆 right next to the set.

HISTORY AND PROGRESS
• Personal records: heaviest weight, best weight for 1, 3, 5, 8 and 10 reps, reps, time and volume.
• A chart for every exercise: best weight, volume, reps or time over a week, a month, three months, a year or all time.
• Weekly, monthly and yearly summaries: workouts, time, volume, sets by muscle group and your week streak.
• Forgot to log a workout? Add it afterwards or correct a past one — records and charts are recalculated.
• Send a template, a workout or a whole period as text — to your coach, for example.

EXERCISES AND SETTINGS
• 53 built-in exercises in English and Russian, plus your own.
• Search and filters by muscle group and equipment.
• Kilograms or pounds, light and dark theme.

Free, no limits: every feature is available right away — no subscriptions, paid extras, ads or sign-up. Your workouts stay on your iPhone.

Questions and suggestions: t.me/setnewloop

## Notes for App Review

English, в поле App Review Information → Notes:

> TrainingLoop needs no account, sign-in or network access. All data stays on the device.
>
> How to test:
> 1. On the Workouts tab, tap the play button next to "Full Body" (an example template). The workout screen opens with the planned sets.
> 2. Enter a weight in the first set and tap its circle. The set is marked done and the rest timer starts.
> 3. Lock the phone. The rest countdown appears on the Lock Screen (Live Activity) and in the Dynamic Island, with +10 and Skip. When the rest ends, the card shows the next set with a Done button that marks it from the Lock Screen.
> 4. Tap Finish to see the summary and save the workout to History. Open Exercises → Barbell Back Squat to see its chart and records (they appear from the second workout with the exercise).
>
> Background audio: the audio background mode plays the rest-end sounds and voice prompts while the screen is locked during a workout; without it the cues stop when the phone locks. The audio session is active only during a workout. Music from other apps keeps playing and is only lowered briefly around each cue.
> If sounds and voice are off, or Silent Mode is not ignored, the end of rest is announced with a local notification instead; permission is asked the first time it is needed.

## Скриншоты

Готовые снимки 6.9″ (1320×2868, PNG без прозрачности) лежат в `docs/appstore/en/` и `docs/appstore/ru/`; для меньших экранов App Store масштабирует их сам. Загружать в этом порядке:

1. `1-templates.png` — шаблоны тренировок с суперсетами.
2. `2-workout.png` — тренировка: прошлый раз, рекорд 🏆 у подхода, таймер отдыха.
3. `3-lock.png` — Live Activity на экране блокировки: отдых с «+10» и «Пропустить».
4. `4-chart.png` — график упражнения и рекорды.
5. `5-history.png` — история тренировок с числом рекордов.
6. `6-summary.png` — сводка за месяц: тоннаж по неделям, календарь.

Сняты в симуляторе iPhone 18 Pro Max (iOS 27), время в статус-баре 9:41, язык системы совпадает с языком снимков. Данные — отладочная история за 10 недель: Debug-сборка с аргументом запуска `-SampleHistory YES` на чистой установке (`TrainingLoop/Models/SampleHistory.swift`). Уменьшенные JPG для сайта и README — в `site/screens/`.
