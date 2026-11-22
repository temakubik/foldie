# Foldie

> **A minimalist native macOS menu bar folder manager** — collect all your menu bar icons into one clean folder, organize them into nested folders & dividers, swipe between folders right in the menu bar, and open them as a **frameless floating list** or a **3D rotating cylinder**.
>
> **Минималистичный нативный менеджер строки меню для macOS** — собирает все иконки строки меню в одну аккуратную папку, позволяет раскладывать их по внутренним папкам и разделителям, переключаться между папками свайпом прямо в строке меню и раскрывать их в виде **парящего списка** или **3D-цилиндра (барабана)**.

---

## English

### What is Foldie?
macOS menu bars get crowded quickly — especially on MacBooks with a notch. **Foldie** places a single sleek folder icon with a live app counter in your menu bar and hides the rest of your status items inside it.

### Key Features
- **One Folder + Live Count Badge**: Keeps your menu bar clean with a single Foldie icon showing how many apps are inside.
- **Swipe Between Folders in the Menu Bar**: Two-finger horizontal swipe left/right right over Foldie's menu bar icon switches between all apps and your custom folders with haptic feedback.
- **Hover or Click to Open (Frameless UI)**: Hovering over Foldie reveals compact floating frosted-glass items directly underneath the icon — no bulky window chrome.
- **Two Display Modes**:
  - **Floating List**: Compact nested folders, custom dividers, and instant app triggering.
  - **3D Cylinder (Drum)**: Tactile 3D rotating wheel with perspective, trackpad/scroll-wheel inertia, keyboard navigation (`↑`/`↓`/`⏎`/`←`), and haptic detents.
- **Color & Monochrome Icon Styles**: Switch between original colorful app icons and sleek monochrome menu-bar-style icons.
- **Full Organizer & Settings Window** *(Right-click Foldie → Settings)*: Organize apps into colored folders with custom SF Symbols, add labeled dividers, drag & drop to reorder, toggle individual app visibility, and one-click auto-collect.
- **Interactive Onboarding**: Step-by-step first-launch guide with drag-and-drop Accessibility setup.
- **100% Native & Private**: Built in pure Swift & SwiftUI (`AppKit`, `ScreenCaptureKit`, `ApplicationServices`), zero third-party dependencies, zero network access.

### Download & Install
1. Download **`Foldie-v1.0.0-macOS-arm64.zip`** from the [Releases](../../releases) page.
2. Unzip and move **`Foldie.app`** to `/Applications`.
3. Launch **`Foldie.app`**.
   > Because this release is locally signed (ad-hoc), on first open macOS Gatekeeper may ask for confirmation: right-click `Foldie.app` → **Open** (or allow in *System Settings → Privacy & Security*), or run `xattr -dr com.apple.quarantine /Applications/Foldie.app`.

### First-Time Permissions (macOS 14–26)
- **Accessibility** (*System Settings → Privacy & Security → Accessibility*): Required to click hidden menu bar items and auto-collect icons. You can drag the `Foldie.app` card right out of Foldie's Permissions tab into the Accessibility list.
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
Строка меню macOS быстро переполняется иконками — особенно на MacBook с вырезом («чёлкой»). **Foldie** добавляет в строку меню одну компактную папку со счётчиком приложений и прячет все остальные иконки внутрь.

### Основные возможности
- **Единая папка со счётчиком приложений**: в строке меню остаётся одна аккуратная иконка Foldie с количеством собранных приложений.
- **Свайп влево/вправо прямо по иконке в строке меню**: проводите двумя пальцами по трекпаду над иконкой Foldie, чтобы мгновенно переключаться между «Всеми приложениями» и вашими папками с тактильной отдачей.
- **Открытие по наведению без лишней оболочки**: наведите курсор на папку Foldie — прямо под ней парят компактные пункты без рамки и лишних кнопок.
- **Два режима отображения**:
  - **Список с папками и разделителями**: компактные сворачиваемые папки, подписанные разделители и быстрый клик по скрытым иконкам.
  - **3D-Цилиндр (барабан)**: интерактивный вращающийся 3D-барабан с перспективой, прокруткой трекпадом/колёсиком, навигацией клавишами (`↑`/`↓`/`⏎`/`←`) и тактильной отдачей.
- **Стили иконок — «Цветные» и «Моно»**: переключайте отображение между оригинальными цветными иконками приложений и минималистичным монохромом.
- **Полноценное окно настроек и сортировки** *(Правый клик по Foldie → «Настройки Foldie...»)*: создание цветных папок с иконками SF Symbols, разделители, перетаскивание, индивидуальные тумблеры отображения приложений и автосбор в один клик.
- **Пошаговый онбординг**: при первом запуске приложение помогает выдать разрешения (включая перетаскивание карточки `Foldie.app` в «Универсальный доступ»).
- **Полностью нативное и локальное**: написано на чистом Swift + SwiftUI без внешних зависимостей и без доступа в сеть.

### Установка готовой сборки
1. Скачайте **`Foldie-v1.0.0-macOS-arm64.zip`** из раздела [Releases](../../releases).
2. Распакуйте архив и перенесите **`Foldie.app`** в папку `/Applications`.
3. Запустите **`Foldie.app`**.
   > Поскольку сборка подписана локальной ad-hoc подписью, при первом запуске macOS может показать предупреждение Gatekeeper: откройте через правый клик → **Открыть** (или разрешите в *Системные настройки → Конфиденциальность и безопасность*), либо выполните `xattr -dr com.apple.quarantine /Applications/Foldie.app`.

### Разрешения при первом запуске (macOS 14–26)
- **Универсальный доступ (Accessibility)**: нужен для клика по скрытым иконкам и автоматического сбора. В окне *Настройки → Разрешения* можно просто перетащить карточку `Foldie.app` прямо в список «Универсальный доступ».
- **Запись экрана (Screen Recording)** *(по желанию)*: для живых миниатюр системных иконок.
- **macOS 26 (Tahoe)**: убедитесь, что **Foldie** включён в *Системные настройки → Строка меню → «Разрешить в строке меню»*.

### Сборка из исходников
Требуется macOS 14+ и Apple Command Line Tools (`swiftc`).
```bash
./build.sh
open Foldie.app
```
