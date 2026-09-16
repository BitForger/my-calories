# Simply Track

Simply Track is a SwiftUI calorie-tracking app built with SwiftData. It helps you log food entries, track daily and weekly calorie goals, and review your consistency over time. The app also includes optional HealthKit sync, reminders, and a quick-start onboarding flow for setup.

## Features

- **Quick Start onboarding** for privacy, HealthKit access, and sync preferences
- **Manual food logging** with name, amount, calories, and time
- **Daily and weekly dashboards** with progress indicators and target summaries
- **Profile-based calorie targets** using age, sex, height, weight, activity level, and goal
- **Dynamic target mode** that estimates BMR and TDEE
- **Food catalog shortcuts** for common entries
- **HealthKit integration** for reading, syncing, and deleting calorie entries
- **Optional reminders** to log calories later in the day
- **SwiftData persistence** with local storage and recovery handling

## Requirements

- Xcode with SwiftUI and SwiftData support
- iPhone and/or Mac run destination, depending on the scheme configuration
- Optional permissions for HealthKit and notifications if you enable those features

## Getting Started

1. Open `simply-track.xcodeproj` in Xcode.
2. Select the `simply-track` scheme.
3. Choose a simulator or connected device.
4. Build and run the app.

When the app launches for the first time, it creates a default profile and seeds a small food catalog automatically.

## Project Structure

```text
simply-track/
├── ContentView.swift      # Main app UI, logging, sync, onboarding
├── Item.swift             # SwiftData models and calorie calculations
├── SettingsView.swift     # Profile and app settings
├── simply_trackApp.swift  # App entry point and model container setup
└── Assets.xcassets        # App icons and asset catalog
```

## Data and Sync Notes

- Entries are stored locally using SwiftData.
- HealthKit sync is optional and can be enabled from the app.
- Reminder notifications are also optional and can be toggled in Settings.
- The app includes a recovery path for incompatible or corrupted SwiftData stores.

## License

No license has been added yet. Add one here if you plan to share the project publicly.
