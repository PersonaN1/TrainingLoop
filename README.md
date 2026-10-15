# TrainingLoop

Дневник силовых тренировок для iPhone от автора [SetLoop](https://github.com/PersonaN1/SetLoop). Бесплатно, без рекламы, без регистрации и без сбора данных.

A workout log for iPhone from the maker of SetLoop. Free, no ads, no sign-up, no data collection.

Статус: разработка. Спецификация — [docs/SPEC.md](docs/SPEC.md), технический план — [docs/TECH.md](docs/TECH.md).

## Сборка

- Xcode 26+ (Swift 6), iOS 17.0+. Проект описан в `project.yml` ([XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46.0); сгенерированный `TrainingLoop.xcodeproj` закоммичен — после правки `project.yml` выполните `xcodegen generate`.
- Подпись: создайте `Config/Local.xcconfig` (вне git) со строкой `DEVELOPMENT_TEAM = <ваш Team ID>`.
- Тесты домена: `xcodebuild test -scheme TrainingLoopCore -destination 'platform=macOS'` в `Packages/TrainingLoopCore` (так же в CI). `swift test` подходит с Xcode 27+; в Xcode 26 он не компилирует String Catalog пакета, и тесты названий упражнений падают.

See [LICENSE](LICENSE) and [CONTRIBUTING.md](CONTRIBUTING.md).
