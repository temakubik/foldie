# Foldie

> **A minimalist native macOS menu bar folder manager** — collect all your menu bar icons into one sleek Liquid-Glass capsule, organize them into top-level folders & dividers, switch folders with trackpad or mouse gestures right in the menu bar, and open them as a **frameless floating list** or a **3D rotating cylinder**.
>
> **Минималистичный нативный менеджер строки меню для macOS** — собирает все иконки строки меню в единую аккуратную капсулу, позволяет раскладывать их по папкам и разделителям, переключаться между папками жестами трекпада или мышкой прямо в строке меню и раскрывать их в виде **парящего списка** или **3D-цилиндра (барабана)**.

---

## English

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
- **100% Native & Private**: Pure Swift & SwiftUI (`AppKit`, `ScreenCaptureKit`, `ApplicationServices`), zero third-party dependencies, zero network access.

### Download & Install
1. Download **`Foldie-v1.1.0-macOS-arm64.zip`** from the [Releases](../../releases) page.
2. Unzip and move **`Foldie.app`** to `/Applications`.
3. Launch **`Foldie.app`**.
   > Because this release is locally signed (ad-hoc), on first open macOS Gatekeeper may ask for confirmation: right-click `Foldie.app` → **Open** (or allow in *System Settings → Privacy & Security*), or run `xattr -dr com.apple.quarantine /Applications/Foldie.app`.

### First-Time Permissions (macOS 14–26)
- **Accessibility** (*System Settings → Privacy & Security → Accessibility*): Required to click hidden menu bar items and auto-collect icons. You can drag the `Foldie.app` card right out of Foldie's Permissions tab into the Accessibility list (and use **Reset stale entry** if upgrading an ad-hoc build).
- **Screen Recording** *(optional)*: Enables live menu bar thumbnails and system item titles.
- **macOS 26 (Tahoe) Menu Bar**: Ensure **Foldie** is enabled in *System Settings → Menu Bar → Allow in the Menu Bar*.

### Build from Source
Requires macOS 14+ and Apple Command Line Tools (`swiftc`).
```bash
git clone https://github.com/temakubik/foldie.git
cd foldie
chmod +x build.sh
./build.sh
open Foldie.app
```

---

## Русский

### Что такое Foldie?
Строка меню macOS быстро переполняется иконками — особенно на MacBook с вырезом («чёлкой»). **Foldie** добавляет в строку меню единую аккуратную капсулу со счётчиком приложений и прячет все остальные иконки внутрь.

### Основные возможности
- **Единая настраиваемая капсула и закреплённые папки**:
  - Капсула фиксированной ширины `[Иконка | Название папки | Счётчик]` с плавной прокруткой длинных названий при наведении — или компактный режим **«Только иконка»**.
  - Выбор формы капсулы в настройках: **Скруглённый** (в стиле системных бейджей macOS), **Капсула** (полное скругление) или **Строгий**.
  - Любую папку (*Утилиты*, *VPN*, *ИИ* и др.) можно **закрепить отдельной капсулой** в строке меню.
- **Быстрое переключение папок — трекпадом и мышкой**:
  - **Трекпад / Magic Mouse**: свайп двумя пальцами влево/вправо по капсуле Foldie или по открытому меню.
  - **Мышка**: горизонтальная прокрутка колёсиком, **`Shift` + колёсико**, либо **зажать левую кнопку и потянуть курсор влево/вправо прямо по капсуле** *(перемещение самой иконки по строке меню macOS по-прежнему работает через `⌘` + перетаскивание)*.
  - Переключение свайпами можно включить или отключить в *Настройки → Поведение и вид*.
- **Автосортировка одной кнопкой**: сканирует приложения из строки меню и раскладывает их по 7 базовым категориям (*ИИ и разработка*, *Сеть и VPN*, *Связь*, *Продуктивность*, *Утилиты*, *Система*, *Прочее*).
- **Открытие по наведению без лишней оболочки**: наведите курсор на капсулу Foldie или на любую закреплённую папку — прямо под ней парят компактные пункты без рамки и лишнего хрома.
- **Два режима отображения**:
  - **Список**: компактные папки, подписанные разделители и быстрый клик по скрытым иконкам.
  - **3D-Цилиндр (барабан)**: интерактивный вращающийся 3D-барабан с фиксированной верхней осью прямо под капсулой, прокруткой трекпадом/колёсиком, навигацией клавишами (`↑`/`↓`/`⏎`/`←`) и тактильной отдачей.
- **Тактильные микро-звуки**: мягкий синтезированный «пуньк» при клике/открытии, направленный звук при свайпе папок и тихий «тик» при вращении 3D-барабана (отключается в *Настройки → Поведение и вид*).
- **Стили иконок — «Цветные» и «Моно»**: переключение между оригинальными цветными иконками приложений и минималистичным монохромом.
- **Полноценное окно настроек и сортировки** *(Правый клик по Foldie → «Настройки Foldie...»)*: создание цветных папок с иконками SF Symbols, разделители, перетаскивание, индивидуальные тумблеры отображения и автосбор в один клик.
- **Полностью нативное и локальное**: чистый Swift + SwiftUI без сторонних зависимостей и без доступа в сеть.

### Установка готовой сборки
1. Скачайте **`Foldie-v1.1.0-macOS-arm64.zip`** из раздела [Releases](../../releases).
2. Распакуйте архив и перенесите **`Foldie.app`** в папку `/Applications`.
3. Запустите **`Foldie.app`**.
   > Поскольку сборка подписана локальной ad-hoc подписью, при первом запуске macOS может показать предупреждение Gatekeeper: откройте через правый клик → **Открыть** (или разрешите в *Системные настройки → Конфиденциальность и безопасность*), либо выполните `xattr -dr com.apple.quarantine /Applications/Foldie.app`.

### Разрешения при первом запуске (macOS 14–26)
- **Универсальный доступ (Accessibility)**: нужен для клика по скрытым иконкам и автоматического сбора. В окне *Настройки → Разрешения* можно перетащить карточку `Foldie.app` прямо в список «Универсальный доступ» (а при обновлении сборки — нажать **«Сбросить старую запись»**).
- **Запись экрана (Screen Recording)** *(по желанию)*: для живых миниатюр системных иконок.
- **macOS 26 (Tahoe)**: убедитесь, что **Foldie** включён в *Системные настройки → Строка меню → «Разрешить в строке меню»*.

### Сборка из исходников
Требуется macOS 14+ и Apple Command Line Tools (`swiftc`).
```bash
./build.sh
open Foldie.app
```
