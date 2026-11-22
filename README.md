# Foldie

<p align="left">
  <a href="#русский"><b>🇷🇺 Русский</b></a> ·
  <a href="#english"><b>🇬🇧 English</b></a> ·
  <a href="https://github.com/temakubik/foldie/releases/latest"><b>⬇️ Скачать v1.2.0 / Download</b></a>
</p>

> **Минималистичный нативный менеджер строки меню для macOS** — собирает все иконки строки меню в единую аккуратную капсулу, позволяет раскладывать их по папкам и разделителям, переключаться между папками жестами трекпада или мышкой прямо в строке меню и раскрывать их в виде **парящего списка** или **3D-цилиндра (барабана)**.
>
> **A minimalist native macOS menu bar folder manager** — collect all your menu bar icons into one sleek Liquid-Glass capsule, organize them into top-level folders & dividers, switch folders with trackpad or mouse gestures right in the menu bar, and open them as a **frameless floating list** or a **3D rotating cylinder**.

---

## Русский

<sub>
  <a href="#что-такое-foldie">О приложении</a> ·
  <a href="#основные-возможности">Возможности</a> ·
  <a href="#установка-готовой-сборки">Установка</a> ·
  <a href="#разрешения-при-первом-запуске-macos-1427">Разрешения</a> ·
  <a href="#сборка-из-исходников">Сборка</a> ·
  <a href="#english">English version →</a>
</sub>

### Что такое Foldie?
Строка меню macOS быстро переполняется иконками — особенно на MacBook с вырезом («чёлкой»). **Foldie** добавляет в строку меню единую аккуратную капсулу со счётчиком приложений и прячет все остальные иконки внутрь.

### Основные возможности
- **Единая настраиваемая капсула и закреплённые папки**:
  - Капсула фиксированной ширины `[Иконка | Название папки | Счётчик]` с плавной прокруткой длинных названий при наведении — или компактный режим **«Только иконка»**.
  - Выбор формы капсулы в настройках: **Скруглённый** (в стиле системных бейджей macOS), **Капсула** (полное скругление) или **Строгий**.
  - Любую папку (*Утилиты*, *VPN*, *ИИ* и др.) можно **закрепить отдельной капсулой** в строке меню.
- **Быстрое переключение папок — трекпадом и мышкой**:
  - **Трекпад / Magic Mouse**: свайп двумя пальцами влево/вправо по капсуле Foldie или по открытому меню.
  - **Мышка**: горизонтальная прокрутка колёсиком, **`Shift` + колёсико**, либо **зажать левую кнопку и потянуть курсор влево/вправо прямо по капсуле** *(перемещение самой иконки в строке меню macOS по-прежнему работает через `⌘` + перетаскивание)*.
  - Переключение свайпами можно включить или отключить в *Настройки → Поведение и вид*.
- **Автосортировка одной кнопкой**: сканирует приложения из строки меню и раскладывает их по 7 базовым категориям (*ИИ и разработка*, *Сеть и VPN*, *Связь*, *Продуктивность*, *Утилиты*, *Система*, *Прочее*).
- **Открытие по наведению без лишней оболочки**: наведите курсор на капсулу Foldie или на любую закреплённую папку — прямо под ней парят компактные пункты без рамки и лишнего хрома.
- **Два режима отображения**:
  - **Список**: компактные папки, подписанные разделители и быстрый клик по скрытым иконкам.
  - **3D-Цилиндр (барабан)**: интерактивный вращающийся 3D-барабан с фиксированной верхней осью прямо под капсулой, прокруткой трекпадом/колёсиком, навигацией клавишами (`↑`/`↓`/`⏎`/`←`) и тактильной отдачей.
- **Тактильные микро-звуки**: мягкий синтезированный «пуньк» при клике/открытии, направленный звук при свайпе папок и тихий «тик» при вращении 3D-барабана (отключается в *Настройки → Поведение и вид*).
- **Стили иконок — «Цветные» и «Моно»**: переключение между оригинальными цветными иконками приложений и минималистичным монохромом.
- **Полноценное окно настроек и сортировки** *(Правый клик по Foldie → «Настройки Foldie...»)*: создание цветных папок с иконками SF Symbols, разделители, перетаскивание, индивидуальные тумблеры отображения и автосбор в один клик.
- **Встроенное автообновление и вкладка «Справка»**: Foldie автоматически проверяет новые релизы на GitHub, скачивает и устанавливает обновления в один клик с автоматическим перезапуском (отключается в *Настройки → Поведение и вид*).
- **Полностью нативное и приватное**: чистый Swift + SwiftUI без сторонних зависимостей, никакой телеметрии (сеть используется только для проверки обновлений на GitHub Releases).

### Установка готовой сборки
1. Скачайте **`Foldie-v1.2.0-macOS-arm64.dmg`** (или `.zip`) со страницы [Releases](https://github.com/temakubik/foldie/releases/latest).
2. Откройте `.dmg` и перетащите **`Foldie.app`** в папку **Applications** (`/Applications`).
3. Запустите **`Foldie.app`**.
   > Поскольку сборка подписана локальной ad-hoc подписью, при первом запуске macOS может показать предупреждение Gatekeeper: откройте через правый клик → **Открыть** (или разрешите в *Системные настройки → Конфиденциальность и безопасность*), либо выполните `xattr -dr com.apple.quarantine /Applications/Foldie.app`.

### Разрешения при первом запуске (macOS 14–27)
- **Скрытие иконок с панели работает автоматически** (Foldie сам привязывается к правому краю строки меню — даже без выдачи системных разрешений).
- **Универсальный доступ (Accessibility)** / **System & App Protection Override (macOS 27.3+)**: нужен, чтобы клики по приложениям внутри Foldie открывали их собственные выпадающие меню строки меню.
  - На macOS 14–26: в окне *Настройки → Разрешения* перетащите карточку `Foldie.app` прямо в список «Универсальный доступ» (при обновлении нажмите **«Сбросить старую запись»**).
  - На macOS 27.3+: Apple перенесла разрешения для сторонних утилит в раздел **System & App Protection Override**. Если приложение отображается серым в окне выбора, сначала снимите карантин (`xattr -dr com.apple.quarantine /Applications/Foldie.app`) либо соберите Foldie локально со своим доверенным сертификатом подписи кода в «Связке ключей».
- **Запись экрана (Screen Recording)** *(по желанию)*: для живых миниатюр системных иконок.
- **macOS 26+**: убедитесь, что **Foldie** включён в *Системные настройки → Строка меню → «Разрешить в строке меню»*.

### Сборка из исходников
Требуется macOS 14+ и Apple Command Line Tools (`swiftc`).
```bash
git clone https://github.com/temakubik/foldie.git
cd foldie
chmod +x build.sh
./build.sh
open Foldie.app
```

---

## English

<sub>
  <a href="#what-is-foldie">About</a> ·
  <a href="#key-features">Features</a> ·
  <a href="#download--install">Download</a> ·
  <a href="#first-time-permissions-macos-1427">Permissions</a> ·
  <a href="#build-from-source">Build</a> ·
  <a href="#русский">↑ Русская версия</a>
</sub>

### What is Foldie?
macOS menu bars get crowded quickly — especially on MacBooks with a notch. **Foldie** places a unified, customizable folder capsule with a live app counter in your menu bar and hides the rest of your status items cleanly inside it.

### Key Features
- **Unified Menu Bar Capsule & Pinned Folder Icons**:
  - Single fixed-width Foldie capsule showing `[Icon | Folder Name | Live Count]` (with smooth hover marquee scrolling for long folder names) — or switch to compact **Icon Only** mode.
  - Customizable capsule shape: **Rounded** (matches native macOS badges), **Capsule** (full pill), or **Subtle** (crisp corners).
  - Or **pin any folder** (e.g. *VPN*, *Utilities*, *AI*) as its own separate colored menu bar capsule.
- **Fast Folder Switching — Trackpad & Mouse**:
  - **Trackpad / Magic Mouse**: two-finger swipe left or right over the Foldie capsule (or over the open dropdown menu).
  - **Mouse**: scroll horizontally with a tilt/thumb wheel, hold **`Shift` + scroll wheel**, or **click and drag horizontally** directly across the Foldie capsule *(hold `⌘` + drag to reposition the icon in the macOS menu bar as usual)*.
  - Can be enabled or disabled anytime in *Settings → Behavior & Appearance*.
- **One-Click Smart Auto-Sort**: Automatically scans menu bar apps and groups them into 7 clean categories (*AI & Dev*, *VPN & Network*, *Communication*, *Productivity*, *Utilities*, *System*, *Other*) using app metadata and bundle identifiers.
- **Hover or Click to Open (Frameless UI)**: Hovering over Foldie (or any pinned folder) reveals compact floating frosted-glass pills directly underneath — no bulky window chrome.
- **Two Display Modes**:
  - **Floating List**: Compact folders, custom dividers, and instant app triggering.
  - **3D Cylinder (Drum)**: Tactile 3D rotating drum anchored right beneath the capsule with perspective, trackpad/scroll-wheel inertia, keyboard navigation (`↑`/`↓`/`⏎`/`←`), and haptic detents.
- **Tactile Micro-Sounds**: Subtle synthesized audio feedback for click/open, directional folder swipes, and 3D drum ticks (toggleable in *Settings → Behavior & Appearance*).
- **Color & Monochrome Icon Styles**: Switch between original colorful app icons and monochrome menu-bar-style icons.
- **Full Organizer & Settings Window** *(Right-click Foldie → Settings)*: Create colored folders with custom SF Symbols, add labeled dividers, drag & drop to reorder, toggle individual app visibility, and one-click auto-collect.
- **Built-In Auto-Updater & Help Tab**: Foldie automatically checks GitHub Releases and downloads/installs updates in one click with seamless relaunch (toggleable in *Settings → Behavior & Appearance*), plus a built-in Help guide right inside Settings.
- **100% Native & Private**: Pure Swift & SwiftUI (`AppKit`, `ScreenCaptureKit`, `ApplicationServices`), zero third-party dependencies, zero telemetry (network is used only for optional GitHub Releases update checks).

### Download & Install
1. Download **`Foldie-v1.2.0-macOS-arm64.dmg`** (or `.zip`) from the [Releases](https://github.com/temakubik/foldie/releases/latest) page.
2. Open the `.dmg` and drag **`Foldie.app`** into **Applications** (`/Applications`).
3. Launch **`Foldie.app`**.
   > Because this release is locally signed (ad-hoc), on first open macOS Gatekeeper may ask for confirmation: right-click `Foldie.app` → **Open** (or allow in *System Settings → Privacy & Security*), or run `xattr -dr com.apple.quarantine /Applications/Foldie.app`.

### First-Time Permissions (macOS 14–27)
- **Menu bar icon hiding works automatically** (Foldie snaps itself to the right edge of third-party items without requiring Accessibility).
- **Accessibility** / **System & App Protection Override (macOS 27.3+)**: required so clicking an app inside Foldie opens that app's own native menu bar dropdown/context menu.
  - On macOS 14–26: drag the `Foldie.app` card from *Settings → Permissions* into Accessibility (use **Reset stale entry** after upgrading an ad-hoc build).
  - On macOS 27.3+: Apple moved third-party automation utilities into **System & App Protection Override**. If Foldie appears greyed out in the picker due to ad-hoc signing/quarantine, run `xattr -dr com.apple.quarantine /Applications/Foldie.app` or build locally with a trusted code-signing certificate in Keychain.
- **Screen Recording** *(optional)*: Enables live menu bar thumbnails and system item titles.
- **macOS 26+ Menu Bar**: Ensure **Foldie** is enabled in *System Settings → Menu Bar → Allow in the Menu Bar*.

### Build from Source
Requires macOS 14+ and Apple Command Line Tools (`swiftc`).
```bash
git clone https://github.com/temakubik/foldie.git
cd foldie
chmod +x build.sh
./build.sh
open Foldie.app
```
