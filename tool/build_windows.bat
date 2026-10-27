@echo off
rem Compila Nido para Windows con Visual Studio 2026.
rem Flutter 3.35 no reconoce VS 2026 y usa una version antigua de MSVC, con la
rem que el SDK C++ de Firebase no enlaza; por eso se compila con CMake + Ninja.
rem Uso: tool\build_windows.bat   (desde la carpeta nido)

setlocal
set VS=C:\Program Files\Microsoft Visual Studio\18\Community
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set PATH=C:\src\flutter\bin;%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%

rem Genera los archivos de Flutter (windows\flutter\ephemeral) si faltan, por
rem ejemplo tras "flutter clean". "flutter build windows" los escribe antes de
rem compilar; su fallo posterior al enlazar con VS 2019 es esperado y se ignora.
call flutter pub get || exit /b 1
if not exist windows\flutter\ephemeral\generated_config.cmake (
  echo Generando la configuracion de Flutter para Windows...
  call flutter build windows --release >nul 2>&1
  if not exist windows\flutter\ephemeral\generated_config.cmake (
    echo No se pudo generar windows\flutter\ephemeral\generated_config.cmake
    exit /b 1
  )
)

cmake -S windows -B build\windows\ninja -G Ninja -DCMAKE_BUILD_TYPE=Release -DFLUTTER_TARGET_PLATFORM=windows-x64 || exit /b 1
cmake --build build\windows\ninja --config Release || exit /b 1
cmake --install build\windows\ninja --config Release || exit /b 1

echo.
echo Listo: build\windows\ninja\runner\nido.exe
endlocal
