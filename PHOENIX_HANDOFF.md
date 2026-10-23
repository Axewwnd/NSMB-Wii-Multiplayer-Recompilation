# PHOENIX HANDOFF — NSMB Wii Multiplayer Recompilation en Redmi Note 11 (spes)

**Fork:** https://github.com/Axewwnd/NSMB-Wii-Multiplayer-Recompilation
**Upstream:** https://github.com/WitherBlitz/NSMB-Wii-Multiplayer-Recompilation
**Última actualización:** 2026-10-23 (sesión de diagnóstico de pantalla negra; ver §9)

---

## 1. Objetivo

APK ARM64 (`arm64-v8a`) que arranque en un **Redmi Note 11 `spes`**: Snapdragon 680,
Kryo 265 (4× Cortex-A73 + 4× Cortex-A53, **ARMv8.0-A**), Adreno 610, Android 11+ (API 30).
Síntoma original del APK oficial: **`SIGILL`** al procesar `Config.toml`.

---

## 2. Estado real del repositorio al reiniciar

| Dato | Valor |
|---|---|
| Rama | `main`, árbol limpio |
| Upstream | fork **al día**: `git log HEAD..upstream/main` vacío; merge-base = `b8f94c2` (HEAD de upstream) |
| Workflows | `build.yml`, `package.yml`, `recomp-test.yml` (upstream) + **`build-android.yml` (solo del fork, no existe en upstream)** |
| Release upstream | `v0.2.2` con `NSMBW-0.2.2-android-arm64.apk` (compilado con NDK r29, clang 21) |
| Datos de juego | `game/` commiteado por el fork (upstream espera `../game/`) |
| Entorno local | Void Linux, sin Android SDK/NDK; **sin dispositivo ADB conectado**; `gh` autenticado como `Axewwnd` |

### Datos del handoff anterior que eran **falsos** (corregidos aquí)

- Decía que `-march=armv8-a` "ya estaba en el script original": **no**, lo agregó el fork, y además **no tenía efecto** (§3).
- Decía `main.dol` de 3.019.336 bytes: son **3.491.808**.
- Citaba el commit actual como `23713a8`: al reiniciar era `85bb6e4`.

---

## 3. Causa raíz (CONFIRMADA en código, no supuesta)

`runtime/cmake/PublicProducts.cmake`, rama `MKW_PLATFORM_ANDROID`:

```cmake
set(MKW_BASELINE_ARCH_FLAG -march=armv8.2-a)   # aplicado a TODOS los targets del producto
```

`-march=armv8.2-a` habilita **LSE** (CAS/LDADD/SWP atómicos) y **RCpc** (LDAPR).
Cortex-A73/A53 (Kryo 265) son ARMv8.0-A y **no implementan LSE**: la primera operación
atómica o load-acquire ejecuta una instrucción ilegal → `SIGILL`. Coincide con el crash al
parsear `Config.toml` (mutex/atomics/refcount de `std::`).

Los `-DCMAKE_C_FLAGS=-DCMAKE_CXX_FLAGS=-march=armv8-a` del fork en `configure-android.ps1`
**nunca sirvieron**: se aplican antes y el flag por-target de `PublicProducts.cmake` los pisa.

### Verificaciones hechas

- **Dawn prebuilt** (`dawn-android-aarch64` v20260603.191052, SHA256 `0e63e8cb…` verificado
  contra el pin): 835 objetos, 823 con código, **11.012.256 bytes** de código desensamblados,
  **0 instrucciones LSE/RCpc**. El prebuilt no es la fuente del SIGILL → basta recompilar lo nuestro.
- El APK oficial v0.2.2 declara en `.comment`: `Android clang 21.0.0`, NDK r29, `for Android 30`.
- Kryo 265 = derivado de Cortex-A73/A53 (ARMv8.0-A). Tablas de SoC y casos públicos de SIGILL
  por LSE en A53/A73 confirman el mecanismo.
- **No verificado en binario**: el desensamblado del `libmain.so` del APK oficial no se completó
  (la máquina local se queda sin recursos con 129 MB). La contraprueba práctica es el gate de CI
  (§5) sobre el `.so` que compilamos nosotros.

---

## 4. Cambios realizados en esta sesión

| Commit | Archivo | Qué |
|---|---|---|
| `47d1279` | `runtime/cmake/PublicProducts.cmake` | Android pasa a `-march=armv8-a` (baseline del ABI). **Éste es el fix del SIGILL.** |
| `999ede6` | `.github/workflows/build-android.yml` | `FETCHCONTENT_SOURCE_DIR_MKW_MBEDTLS_UPSTREAM` (el nombre real del declare); Gradle 8.7 pinneado (el runner trae 9.x y AGP 8.5.2 no lo soporta); timeout 120→300 min; gate anti-LSE sobre `libmain.so`; SHA-256 del APK en el summary |
| `e7ae859` | `aurora-main/cmake/AuroraDawnProvider.cmake` | El paquete Dawn exporta `…/sysroot/…/aarch64-linux-android/28/liblog.so` como **ruta absoluta del NDK del que lo compiló**. Se reescribe a `log` para que el toolchain la re-ubique. Sin esto, Ninja muere con *"no known rule to make it"* sin compilar nada |
| `2c55f79` | `.github/workflows/build-android.yml` | La ruta del NDK se deriva de `NDK_VERSION` en cada paso (configure/stage/gate) y el chequeo de versión **falla duro**. Antes, un `ANDROID_NDK_HOME` heredado hacía que el configure usara **NDK 27** con el NDK 29 instalado |

---

## 5. Cronología del CI (mapa para no repetir pasos)

| Run | Resultado | Causa |
|---|---|---|
| `39889930964` | falla en *Configure* | `mkw_mbedtls` referenciaba `MbedTLS::mbedtls`; el declare se llama `mkw_mbedtls_upstream` → el `FETCHCONTENT_SOURCE_DIR_MBEDTLS` genérico no lo alcanzaba |
| `39890657223` | *Configure* OK, falla *Build* | (a) Ninja pedía un `liblog.so` en ruta **de Linux** del NDK del que se compiló Dawn; (b) el configure había usado **NDK 27.3.13750724** pese a tener el 29 instalado y exportado |
| `39891535024` | **en curso** | con Dawn saneado y NDK 29 pinneado |

Lecciones de los runs previos a esta sesión (no repetir): `setup-android@v3` no acepta
`ndk;r29c`; no crear symlinks de sysroot; no hardcodear linker flags por API; no usar
`Expand-Archive` con `.tar.gz`.

---

## 6. Flujo real de compilación (para no adivinar)

1. **Translator (.NET 8)**: `main.dol` + `nsmbw_linked.rel` → `generated/functions`,
   `generated/build_shards/shards.cmake` (≈39.400 funciones).
2. **CMake + Ninja + NDK 29**: `runtime/` + `aurora-main/` + dependencias fijadas
   (`Launcher/artifacts/dependencies`, `FETCHCONTENT_FULLY_DISCONNECTED=ON`) →
   **`libmain.so`** (una sola biblioteca; libc++ estática, `ANDROID_PLATFORM=android-30`).
3. **Stage**: `llvm-strip` → `android/native/jniLibs/arm64-v8a/`; `dsp_coef.bin`, `cacert.pem`,
   `initial_pipeline_cache.db`, `wii_bootstrap/` → `android/native/assets/runtime/`.
4. **Gradle** `assembleRelease` (firmado con la clave debug, instalable directo).

El APK **no contiene datos del juego**: se importan en el teléfono con
*"Import from Extracted Game Data Folder…"* o *"Import Game Data Zip…"* (ya existe en
`LauncherActivity.java`).

---

## 7. Pendientes

1. **Build en curso** `39891535024`: confirmar que pasa el gate anti-LSE y que Gradle produce el APK.
   Si el build nativo muere por memoria/tiempo, ajustar `--parallel` (hoy 10) o los timeouts —
   **no** tocar los flags de arquitectura.
2. **Riesgo abierto — datos del juego**: `game/main.dol` tiene SHA256 `166eb6b7…`, **distinto** del
   dump limpio SMNE01 rev 1 que espera el repo (`6d755ec2…`). El fork además relajó ese chequeo en
   `unpack_game.py`. Se compila y traduce igual, pero si el`.dol` viene de una ISO modificada puede
   haber diferencias de comportamiento. No se descargó ni se borró nada: decidir con el usuario.
3. **Prueba en el Redmi** (nada de esto vale sin esto): conectar por ADB, `adb install -r`,
   importar datos, verificar que no hay `SIGILL` al leer `Config.toml` y que el juego arranca.
   Registrar SHA-256 del APK que funcione.
4. **Limpieza**: borrar runs fallidos viejos **después** de guardar logs; `PHOENIX_HANDOFF.md`
   y `phoenix-work/` local son los únicos artefactos de esta sesión.

---

## 8. Rollback

- Fix de arquitectura: `git revert 47d1279` (vuelve a ARMv8.2-A; solo tiene sentido si el
  dispositivo objetivo cambia a Cortex-A55/A75 o superior).
- CI: `git revert <commit del workflow>`; el build vuelve al estado anterior sin tocar código.
- Nada de esto toca `game/`, los APK originales ni configuración del sistema.

---

## 9. Diagnóstico de pantalla negra en Redmi Note 11 (`spes`)

### Síntoma
La APK se abre, muestra el menú, pero al darle al botón "play" para iniciar la partida queda en pantalla negra. El audio del juego suena (se reproduce continuamente), lo que indica que el proceso del juego está vivo pero no renderiza nada.

### Causa 1 — MIUI SwipeUpClean mata el proceso `:game` (CONFIRMADA y CORREGIDA)

`GameActivity` usaba `android:process=":game"` (proceso aislado). MIUI's SwipeUpClean detecta este proceso como background (adj=200) aunque `GameActivity` sea visible, y lo mata con `SIGKILL`. Esto crea un loop kill→restart→kill que el usuario percibe como pantalla negra.

**Evidencia en logcat:**
```
ProcessSceneCleaner: SwipeUpClean: kill procName=com.wither.nsmbw:game info=AS:2002
ActivityManager: Killing 22444:com.wither.nsmbw:game/u0a581 (adj 200): SwipeUpClean
```

**Fix:** Commit `c596ec3` — se eliminó `android:process=":game"` de `android/app/src/main/AndroidManifest.xml`. El juego ahora corre en el proceso principal (`com.wither.nsmbw`) donde SwipeUpClean no lo mata.

### Causa 2 — Dawn no puede crear AHardwareBuffer con depth buffer en Adreno 610 (CONFIRMADA, PENDIENTE DE FIX)

Después de fix #1, el proceso vive pero hay pantalla negra. El logcat muestra:

```
E AdrenoUtils: <adreno_init_memory_layout:4723>: Memory Layout input parameter validation failed!
E qdgralloc: GetGpuResourceSizeAndDimensions Graphics metadata init failed
E GraphicBufferAllocator: Failed to allocate (4 x 4) layerCount 1 format 56 usage b00: 1
E GraphicBufferAllocator: Failed to allocate (4 x 4) layerCount 1 format 59 usage b00: 1
E AHardwareBuffer: GraphicBuffer(w=4, h=4, lc=1) failed (Unknown error -1)
```

El formato 56 = `D16_UNORM`, formato 59 = `D32_FLOAT` (depth buffers). Dawn/Aurora está hardcodeado con `depthFormat = Depth32Float` en `aurora-main/lib/webgpu/gpu.cpp:977`. El controlador Adreno 610 de Xiaomi no soporta crear `AHardwareBuffer` con estos formatos de depth, por lo que Dawn falla al inicializar el renderizado y no se dibuja nada en pantalla.

**Evidencia:** El proceso del juego (PID 24969) estuvo vivo 59+ segundos con audio reproduciéndose, pero sin mensajes de renderizado de Dawn después de los fallos de `qdgralloc`.

**Fix propuesto (pendiente):** Modificar `aurora-main/lib/webgpu/gpu.cpp:977` para cambiar `wgpu::TextureFormat::Depth32Float` por un formato más compatible (ej. `Depth24Plus` o `Depth16`). Requiere recompilación y prueba en el dispositivo.

**Logs de diagnóstico:** `/home/kett/phoenix-diagnostics/blackscreen-postfix-20261023-125858/logcat.txt` (captura completa del fallo con el fix del manifest aplicado).

---

## 10. Criterios de aceptación

| Criterio | Cómo se verifica |
|---|---|
| Compila sin errores | workflow `build-android.yml` en verde |
| NDK 29 real | paso *Verify NDK version* (ahora falla duro si no) |
| Baseline ARMv8-A | paso *Verify ARMv8-A baseline*: 0 instrucciones LSE/RCpc en `libmain.so` |
| APK arm64 | `lib/arm64-v8a/libmain.so` dentro del APK, SHA-256 en el run summary |
| Sin `SIGILL` en `spes` | APK instalado y lanzado en Redmi — menú abre, juego inicia sin crash |
| Sin pantalla negra en `spes` | Al darle "play" desde el menú, el juego muestra una escena jugable (pendiente de fix #2) |
