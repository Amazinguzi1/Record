@echo off
chcp 65001 >nul
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo.
  echo [错误] 没检测到 flutter 命令。
  echo 请先安装 Flutter SDK 并把它的 bin 目录加入系统 PATH，然后再运行本脚本。
  echo 安装说明: https://docs.flutter.dev/get-started/install/windows
  echo.
  pause
  exit /b 1
)

echo [1/5] 备份当前源码到 .backup ...
if not exist .backup mkdir .backup
copy /Y "lib\main.dart" ".backup\main.dart" >nul
copy /Y "lib\db.dart" ".backup\db.dart" >nul
copy /Y "lib\category_page.dart" ".backup\category_page.dart" >nul
copy /Y "lib\category_icons.dart" ".backup\category_icons.dart" >nul
copy /Y "pubspec.yaml" ".backup\pubspec.yaml" >nul

echo [2/5] 清理非 Android 平台并生成 android 工程 ...
if exist ios rmdir /S /Q ios
if exist windows rmdir /S /Q windows
if exist web rmdir /S /Q web
if exist linux rmdir /S /Q linux
if exist macos rmdir /S /Q macos
call flutter create --project-name simple_book --platforms=android .
if errorlevel 1 goto :fail

echo [3/5] 恢复自定义源码（防止被模板覆盖）...
copy /Y ".backup\main.dart" "lib\main.dart" >nul
copy /Y ".backup\db.dart" "lib\db.dart" >nul
copy /Y ".backup\category_page.dart" "lib\category_page.dart" >nul
copy /Y ".backup\category_icons.dart" "lib\category_icons.dart" >nul
copy /Y ".backup\pubspec.yaml" "pubspec.yaml" >nul
if exist "test\widget_test.dart" del /q "test\widget_test.dart"

echo [4/5] 拉取依赖 flutter pub get ...
call flutter pub get
if errorlevel 1 goto :fail

echo [5/5] 完成。
echo.
echo 接下来：
echo   1) 用 USB 连接手机并打开开发者调试，或启动模拟器
echo   2) 执行: flutter devices   检查设备
echo   3) 执行: flutter run
echo.
echo 提示：本 App 仅面向 Android。debug 模式较慢属正常，测真实流畅度请用 flutter run --release
echo.
pause
exit /b 0

:fail
echo.
echo [错误] 执行失败，请把上面的报错信息发给你的助手。
pause
exit /b 1
