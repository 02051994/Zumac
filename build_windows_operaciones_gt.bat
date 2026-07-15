@echo off
flutter build windows --release
if exist "build\windows\x64\runner\Zumac" rmdir /s /q "build\windows\x64\runner\Zumac"
xcopy /E /I /Y "build\windows\x64\runner\Release" "build\windows\x64\runner\Zumac"
echo Carpeta final generada: build\windows\x64\runner\Zumac
