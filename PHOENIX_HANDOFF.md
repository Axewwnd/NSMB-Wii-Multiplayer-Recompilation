# PHOENIX HANDOFF — NSMB Wii Multiplayer Recompilation APK for Redmi Note 11 (spes)

**Repositorio:** https://github.com/Axewwnd/NSMB-Wii-Multiplayer-Recompilation  
**Upstream:** https://github.com/WitherBlitz/NSMB-Wii-Multiplayer-Recompilation  
**Fecha:** 2026-10-23  
**Rama actual:** `main` (sincronizada con origin/main)

---

## 1. Objetivo del proyecto (Codename PHOENIX)

Compilar un **APK Android ARM64 (arm64-v8a)** que:
- Funcione en **Redmi Note 11 (codename `spes`)**: Snapdragon 680, CPU Kryo 265 (Cortex-A53/A73), GPU Adreno 610
- Android 11+ (API 30), Vulkan 1.1+
- Incluya la opción **"Import from Extracted Game Data Folder"** para que el usuario importe sus datos del juego en el dispositivo
- **No requiera recompilar el juego en CI** — el APK debe contener `libmain.so` ya compilado
- **Baseline ARMv8-A** (`-march=armv8-a`) para evitar `SIGILL` por instrucciones CRC32/AES/LSE/Atomics no presentes en Kryo 265

---

## 2. Arquitectura y problema original

### Flujo de compilación original (upstream, Windows local)
1. **Translator (.NET 8)**: Convierte `main.dol` + RELs → C++ (`generated/functions/`, `generated/build_shards/`)
2. **CMake + Ninja + NDK 29 (clang)**: Compila runtime + juego traducido + dependencias (SDL3, Dawn, abseil, fmt, freetype, imgui, libusb, libpng, sqlite3, tracy, xxhash, zlib, zstd, MbedTLS) → **`libmain.so`** (única biblioteca nativa)
3. **stage-android.ps1**: `llvm-strip` de `libmain.so` → `android/native/jniLibs/arm64-v8a/libmain.so` + assets runtime → `android/native/assets/runtime/`
4. **Gradle**: Compila `android/app` → **APK final** con `libmain.so` embebido

### Problema original
El APK precompilado (release oficial) fallaba en `spes` con **`SIGILL (Illegal Instruction)`** al parsear `Config.toml`.  
**Hipótesis confirmada por análisis previo**: `libmain.so` compilado con instrucciones ARMv8.2+ (CRC32, AES, LSE, atomics) que **Kryo 265 no soporta** (baseline ARMv8-A / Cortex-A53/A73).

### Solución aplicada en código fuente
- `projects/nsmbw/tools/configure-android.ps1` (original) ya incluye:
  ```powershell
  '-DCMAKE_C_FLAGS=-march=armv8-a',
  '-DCMAKE_CXX_FLAGS=-march=armv8-a',
  ```
- `recomp.yml` ya apunta a `game/main.dol` (repo root) con SHA256 verificado: `166eb6b7cca21418e316a6cfbf1bfbf0a213eb8f6396d42126a1482bb764a955`

---

## 3. Estado real del repositorio (verificado 2026-10-23)

### Commits recientes (main)
```
23713a8 ci: fix NDK version pin and Android dependencies
611a1cf ci: restore original build mechanism with proper Android workflow
b79d15f ci: use original Windows build scripts with proper CI paths
c5afa5f ci: add Android API 30 platform and fix NDK sysroot symlink
d220960 ci: add explicit linker flags to force API 30 libraries
... (parches temporales de CI previos)
```

### Archivos eliminados (scripts CI alternativos — **NO restaurar**)
- `projects/nsmbw/tools/configure-android-ci.ps1` ❌
- `projects/nsmbw/tools/build-android-ci.ps1` ❌
- `projects/nsmbw/tools/stage-android-ci.ps1` ❌
- `Launcher/Prepare-Dependencies-ci.ps1` ❌

### Archivos originales restaurados (usar estos)
- `projects/nsmbw/tools/configure-android.ps1` ✅ (contiene `-march=armv8-a`)
- `projects/nsmbw/tools/build-android.ps1` ✅
- `projects/nsmbw/tools/stage-android.ps1` ✅
- `Launcher/Prepare-PortableTools.ps1` ✅
- `Launcher/Prepare-Dependencies.ps1` ✅ (para Windows; CI usa versión inline adaptada)

### Datos del juego (ya en repo, **no tocar**)
```
game/
  main.dol              (3,019,336 bytes, SHA256 verificado)
  nsmbw_linked.rel      (4,349,568 bytes, prelinked)
  d_basesNP.rel
  d_en_bossNP.rel
  d_enemiesNP.rel
  d_profileNP.rel
  nsmbw_rel_layout.json
```

### Workflow actual: `.github/workflows/build-android.yml`
- Usa **scripts originales adaptados para CI** (paths `GITHUB_WORKSPACE`, `ANDROID_NDK_HOME`)
- **ARMv8-A baseline** preservado en configure step (`-DCMAKE_C_FLAGS=-march=armv8-a`, `-DCMAKE_CXX_FLAGS=-march=armv8-a`)
- Dependencias Android: SDL, abseil, MbedTLS 3.6.7, **dawn_prebuilt_android (aarch64)**, fmt, freetype, imgui, libusb, libpng, sqlite3, tracy, xxhash, zlib, zstd
- **Salta dependencias Windows-only**: `dawn_prebuilt` (Windows), `cppwinrt-tool` (UWP)
- `FETCHCONTENT_FULLY_DISCONNECTED=ON` con fuentes fijadas

---

## 4. Workflow a usar vs. no usar

| Workflow | Estado | Acción |
|----------|--------|--------|
| `.github/workflows/build-android.yml` (actual) | **ACTIVO** — usa scripts originales | **Mantener y corregir** |
| `.github/workflows/build.yml` (upstream) | Solo translator/test/macOS | Referencia, no compila Android |
| `.github/workflows/package.yml` (upstream) | Installers Linux/Win/macOS | Referencia |
| Scripts `*-ci.ps1` eliminados | Eliminados en commit 611a1cf | **No recrear** |

---

## 5. Último error de CI (Run ID: 39885732936)

**Fallo:** `Install Android SDK/NDK (pinned NDK 29)`  
**Causa:** `android-actions/setup-android@v3` no reconoce `ndk;r29c` como identificador válido.

```
Warning: Failed to find package 'ndk;r29c'
Error: The process 'C:\Android\android-sdk\cmdline-tools\16.0\bin\sdkmanager.bat' failed with exit code 1
```

**Evidencia:** El runner instala NDK 27.3.13750724 (r27d) en lugar de 29.0.14206865 (r29c). El Dawn prebuilt `dawn-android-aarch64` v20260603.191052 **requiere NDK 29** (toolchain con el que fue compilado).

**Runs fallidos recientes:**
- 39885732936 — NDK pin `ndk;r29c` inválido
- 39885029195 — NDK 27 instalado en lugar de 29 (pin `ndk;29.0.14206865` ignorado)
- 39883603058 — liblog.so API 28 vs 30 (symlink workaround fallido)
- 39879170320 — mismo error liblog.so

---

## 6. Acciones realizadas y errores a NO repetir

### ✅ Hecho (conservar)
- Flags `-march=armv8-a` en `configure-android.ps1` original
- `recomp.yml` con paths correctos y SHA256 verificado
- Game data en `game/` (main.dol + nsmbw_linked.rel + RELs)
- Workflow usando scripts originales (no `*-ci.ps1`)
- Dependencias Android-only inline en workflow (sin `Prepare-Dependencies-ci.ps1`)

### ❌ Errores a NO repetir
- **No usar `ndk;r29c` ni `ndk;29.0.14206865`** en `setup-android@v3` — no funcionan
- **No crear symlinks artificiales** `/usr/local/lib/android/.../28 → 30` — el runner es Windows, paths son `C:\Android\...`
- **No añadir linker flags hardcodeados** (`-DCMAKE_SHARED_LINKER_FLAGS=.../28/...`) — parche frágil
- **No llamar `Prepare-Dependencies.ps1` completo en CI** — baja `dawn_prebuilt` (Windows) y `cppwinrt-tool` innecesarios
- **No asumir que `ANDROID_NDK_HOME` apunta al NDK correcto** — verificar versión real

---

## 7. Próximo paso concreto

### Problema a resolver: **Instalar NDK 29.0.14206865 (r29c) en Windows runner**

**Opciones investigadas:**
1. **Instalar manualmente** con `sdkmanager "ndk;29.0.14206865"` en step `shell: cmd` o `pwsh` **antes** de `setup-android`
2. **Descargar NDK 29 ZIP** desde `dl.google.com` y extraer a `C:\Android\android-sdk\ndk\29.0.14206865`
3. **Usar `android-actions/setup-android@v3` solo para SDK/platforms** y gestionar NDK aparte

**Archivos a modificar:**
- `.github/workflows/build-android.yml` — step "Install Android SDK/NDK"

**Comando de verificación NDK 29:**
```powershell
$ndk = "C:\Android\android-sdk\ndk\29.0.14206865"
Test-Path "$ndk\build\cmake\android.toolchain.cmake"
Get-Content "$ndk\source.properties" | Select-String "29\.0\.14206865"
```

---

## 8. Criterios de aceptación (Definition of Done)

| Criterio | Verificación |
|----------|--------------|
| **CI compila sin errores** | Workflow `build-android.yml` pasa (verde) |
| **NDK 29 usado** | Log muestra `Pkg.Revision = 29.0.14206865` |
| **ARMv8-A baseline aplicado** | `CMAKE_C_FLAGS` y `CMAKE_CXX_FLAGS` contienen `-march=armv8-a` en configure log |
| **libmain.so generado** | `android-build/libmain.so` existe, ~15-25 MB |
| **APK generado** | `android/app/build/outputs/apk/release/app-release.apk` existe |
| **APK arm64-v8a** | `unzip -l app-release.apk | grep libmain.so` → `lib/arm64-v8a/libmain.so` |
| **SHA-256 del APK registrado** | `sha256sum app-release.apk` en logs/artifact |
| **Sin SIGILL en spes** | **Prueba real en dispositivo** (fase final) |

---

## 9. Reglas de trabajo obligatorias

1. **Auditoría previa**: `git status`, `git log`, leer workflow y scripts antes de tocar nada
2. **Cambios mínimos**: Un fix por commit, un commit por PR/push
3. **Pruebas verificables**: Cada cambio → push → watch CI → analizar logs → decidir siguiente paso
4. **Rollback inmediato**: Si un cambio rompe algo que funcionaba, `git revert` al commit anterior
5. **Preservar estado**: No borrar logs de runs fallidos hasta extraer evidencia; no borrar artifacts válidos
6. **Limpieza controlada**: `gh run delete` solo runs fallidos **después** de guardar logs relevantes
7. **No especular**: Un cambio por hipótesis verificada; no 쌓ar parches "por si acaso"
8. **Datos del juego intocables**: `game/` no se modifica, no se borra, no se regenera en CI

---

## 10. Instrucciones de inicio para nuevo chat

> **COPIA ESTE BLOQUE AL INICIAR EL NUEVO CHAT:**
>
> ```
> Contexto: Proyecto PHOENIX — NSMB Wii Multiplayer Recompilation APK para Redmi Note 11 `spes` (Snapdragon 680 / Kryo 265 / Adreno 610).
>
> Repositorio: https://github.com/Axewwnd/NSMB-Wii-Multiplayer-Recompilation (fork de WitherBlitz/NSMB-Wii-Multiplayer-Recompilation)
>
> Estado actual:
> - Rama `main` en commit 23713a8 "ci: fix NDK version pin and Android dependencies"
> - Workflow `.github/workflows/build-android.yml` usa scripts originales (`configure-android.ps1`, `build-android.ps1`, `stage-android.ps1`) adaptados para CI
> - ARMv8-A baseline (`-march=armv8-a`) ya en configure script original
> - Game data en `game/` (main.dol SHA256 verificado, nsmbw_linked.rel prelinked)
> - **Último fallo CI (run 39885732936)**: `setup-android@v3` no acepta `ndk;r29c` — instala NDK 27 en lugar de 29
> - Dawn prebuilt Android requiere NDK 29 (toolchain coincidente)
>
> Próxima acción: Corregir instalación de NDK 29.0.14206865 en Windows runner (instalación manual vía sdkmanager o descarga ZIP) y re-ejecutar workflow.
>
> Documento de referencia: `PHOENIX_HANDOFF.md` en raíz del repo.
> ```
>
> **No repitas la auditoría completa.** Verifica `git log --oneline -5`, lee el workflow actual, y continúa desde el fix de NDK 29.

---

## 11. Limpieza de runs fallidos (pendiente)

Cuando el build pase, ejecutar:
```bash
# Conservar logs de runs fallidos relevantes primero
gh run view 39885732936 -R Axewwnd/NSMB-Wii-Multiplayer-Recompilation --log > /tmp/run-39885732936.log
gh run view 39885029195 -R Axewwnd/NSMB-Wii-Multiplayer-Recompilation --log > /tmp/run-39885029195.log

# Luego borrar runs fallidos antiguos (mantener últimos 2-3 para comparación)
gh run delete 39883603058 39879170320 39878417375 39877971492 -R Axewwnd/NSMB-Wii-Multiplayer-Recompilation
```

---

## 12. Verificación final en dispositivo (fase posterior a CI exitoso)

1. Descargar artifact APK del run exitoso
2. `adb install -r app-release.apk` en Redmi Note 11
3. Abrir app → "Import from Extracted Game Data Folder" → seleccionar carpeta con `main.dol` + RELs extraídos en el teléfono
4. Verificar: **sin crash al parsear Config.toml**, juego inicia, 60 fps estables
5. Registrar SHA-256 del APK funcional

---

**Fin del documento PHOENIX_HANDOFF.md**  
*Generado automáticamente desde estado real del repositorio 2026-10-23*