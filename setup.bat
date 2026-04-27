@echo off
echo Initializing smartCMR Flutter project...
flutter create --org com.smartcmr --project-name smartcmr .
echo.
echo Running pub get...
flutter pub get
echo.
echo smartCMR is ready!
echo Run 'flutter run' to start the app on your device.
pause
