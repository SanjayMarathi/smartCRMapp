# smartCMR Flutter App

This folder now contains a Flutter mobile rebuild of the original SmartCRM web app.

## Included Features

- Landing and onboarding screen
- Sign in and sign up with Firebase Auth
- Real-time lead dashboard from Firestore
- Create and edit lead flows
- Stage movement, filters, and pipeline metrics
- Reports with CSV and PDF export
- Lead reminders and communication logs
- AI assistant using the same Hugging Face endpoint
- About, privacy, and support pages
- Light and dark theme toggle

## Tech Stack

- Flutter
- Firebase Auth
- Cloud Firestore
- Hosted AI endpoint: `https://crmlead-crmllm.hf.space/generate`

## Project Layout

- `lib/main.dart`: app UI, services, models, theme, and navigation
- `assets/branding/smartcmr_logo.svg`: logo reused from the old app
- `assets/branding/hero.png`: hero illustration reused from the old app
- `pubspec.yaml`: Flutter dependencies

## Firebase Setup

The mobile app uses the same Firebase project/data model as the old web app, but Flutter mobile needs platform-specific Firebase values.

Pass them with `--dart-define` when you run the app:

```bash
flutter run ^
  --dart-define=FIREBASE_PROJECT_ID=your-project-id ^
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=your-sender-id ^
  --dart-define=FIREBASE_STORAGE_BUCKET=your-storage-bucket ^
  --dart-define=FIREBASE_ANDROID_API_KEY=your-android-api-key ^
  --dart-define=FIREBASE_ANDROID_APP_ID=your-android-app-id ^
  --dart-define=FIREBASE_IOS_API_KEY=your-ios-api-key ^
  --dart-define=FIREBASE_IOS_APP_ID=your-ios-app-id ^
  --dart-define=FIREBASE_IOS_BUNDLE_ID=your.ios.bundle.id
```

Optional values:

```bash
--dart-define=FIREBASE_AUTH_DOMAIN=your-auth-domain
```

## First-Time Bootstrap

Flutter is not installed in this environment, so the native platform folders were not generated automatically here.

Once Flutter is installed, run this from the project root:

```bash
flutter create .
flutter pub get
flutter run
```

That will generate the `android/`, `ios/`, and other platform folders around the app code already added in this repository.

## Notes

- Firestore collections stay the same: `leads`, `leads/{id}/notes`, and `leads/{id}/reminders`
- The sign-in behavior still supports normal email input and the `@smartcrm.app` fallback
- Exports are mobile-friendly: CSV is shared through the device share sheet and PDF uses the printing/share flow
