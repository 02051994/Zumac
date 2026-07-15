@echo off
flutter build apk --release
if exist "build\app\outputs\flutter-apk\Operaciones_gt_android.apk" del /q "build\app\outputs\flutter-apk\Operaciones_gt_android.apk"
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\Operaciones_gt_android.apk"
echo APK final generado: build\app\outputs\flutter-apk\Operaciones_gt_android.apk
