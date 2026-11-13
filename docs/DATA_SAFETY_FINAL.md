# Deep Bounce 1.2.1 — відповіді для Play Console → Data safety

Складено за фактичним кодом і SDK збірки 1.2.1 (`com.deepbounce.game`). Перед відправкою звір із актуальними
сторінками Google (посилання внизу) — Google іноді змінює формулювання.

## Що є в грі й що передає дані

| Компонент | Що робить | Передає дані з пристрою? |
|---|---|---|
| Код гри (Godot) | прогрес, налаштування, журнал покупок і нагород, діагностичний журнал — лише у файлах на пристрої | **Ні** — жодного мережевого виклику в коді гри; резервне копіювання Android вимкнене (`allowBackup=false`) |
| Google Mobile Ads SDK 24.9.0 (AdMob) | rewarded + interstitial | **Так** — у Google |
| Google UMP 3.2.0 | форма згоди | **Так** — у Google (стан згоди, приблизний регіон за IP) |
| Google Play Billing 9.1.0 | покупки | обмін лише з Google Play для проведення оплати; розробнику нічого не передається |
| Google Play Games Services v2 | таблиці лідерів | **У 1.2.1 вимкнено** (ID проєкту в конфігурації порожній — SDK не запускається) |
| Google Play In-App Review | картка оцінки | дані не отримує ні гра, ні розробник |

## Перші питання анкети

| Питання | Відповідь |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (SDK Google працюють лише через HTTPS) |
| Do you provide a way for users to request that their data is deleted? | **No** — акаунтів немає, розробник не зберігає даних про користувачів; локальні дані видаляються разом із грою, рекламний ID — у налаштуваннях Android (це пояснено в Privacy Policy) |

## Типи даних — точні відповіді

Позначки в Play Console: **Collected** = дані залишають пристрій; **Shared** = передаються третій стороні,
яка використовує їх у власних цілях. Google як рекламна мережа використовує ці дані у своїх цілях
(показ і вимірювання реклами), тому для даних AdMob виняток «service provider» **не застосовується** → Shared.

### 1. Location → Approximate location
- **Collected: так. Shared: так** (Google AdMob/UMP визначають регіон за IP-адресою).
- Processed ephemerally: **ні**.
- Required or optional: **Required** (без цього неможлива реклама в безкоштовній версії; у ЄЕЗ згода UMP
  впливає на персоналізацію, але не вимикає обробку повністю).
- Purposes: **Advertising or marketing**, **Fraud prevention, security, and compliance**.
- Precise location — **не позначати** (гра не має дозволу на геолокацію).

### 2. App activity → App interactions
- **Collected: так. Shared: так** (покази, кліки, перегляд відео з нагородою — AdMob).
- Ephemeral: **ні**. Required: **Required**.
- Purposes: **Advertising or marketing**, **Analytics**.
- Інші пункти App activity (In-app search history, Installed apps, Other user-generated content, Other actions) — **не позначати**.

### 3. App info and performance → Crash logs
- **Collected: так. Shared: так** (Google Mobile Ads SDK надсилає звіти про збої, пов'язані з рекламою).
- Ephemeral: **ні**. Required: **Required**.
- Purposes: **Analytics**, **Fraud prevention, security, and compliance**.

### 4. App info and performance → Diagnostics
- **Collected: так. Shared: так** (продуктивність, версія ОС і застосунку — Google Mobile Ads SDK).
- Ephemeral: **ні**. Required: **Required**.
- Purposes: **Analytics**, **Fraud prevention, security, and compliance**.
- Other app performance data — не позначати.

### 5. Device or other IDs
- **Collected: так. Shared: так** (рекламний ID Android, App set ID — Google Mobile Ads SDK).
- Ephemeral: **ні**. Required: **Required** (користувач може скинути/видалити рекламний ID у налаштуваннях Android;
  власник «Без реклами» не передає нічого, бо SDK не запускається).
- Purposes: **Advertising or marketing**, **Analytics**, **Fraud prevention, security, and compliance**.

### 6. Financial info → Purchase history
- **Не позначати ні Collected, ні Shared.** Гра не передає дані покупок нікуди: ID товару, purchase token і номер
  замовлення зберігаються лише у файлі на пристрої. Обмін із Google Play Billing — це обробка платежу самим
  Google Play, а не збір даних застосунком.
- Решта Financial info (Payment info, Credit score, Other) — не позначати.

### 7. Personal info → User IDs
- **У версії 1.2.1 — не позначати**: Play Games Services вимкнено, ідентифікатор гравця нікуди не надсилається.
- **Після ввімкнення таблиць лідерів** (коли впишемо ID проєкту Play Ігор): позначити **Collected** (ID гравця
  Play Games передається в Google Play Games разом із результатами), Shared — **ні** (Google тут виконує функцію,
  яку замовив розробник: зберігає й показує таблиці лідерів — виняток service provider), Ephemeral — ні,
  **Optional** (лише для гравців, які увійшли в Play Ігри), Purpose — **App functionality**. Цей пункт звір зі
  сторінкою Google про Data safety для Play Games Services перед відправкою.

### 8. Усе інше — не позначати
Name, Email address, Address, Phone number, Race and ethnicity, Political or religious beliefs, Sexual orientation,
Other info; Health and fitness; Messages; Photos and videos; Audio files; Files and docs; Calendar; Contacts;
Web browsing history; Precise location.

## Інші анкети App content (коротко)

| Розділ | Відповідь |
|---|---|
| Ads | Yes, my app contains ads |
| Advertising ID | Yes — Advertising or marketing, Analytics, Fraud prevention, security, and compliance |
| App access | All functionality is available without special access |
| Target audience | 13–15, 16–17, 18+ (не обирати молодші групи) |
| Content rating | Game; насильства, страшного, азартних ігор, спілкування користувачів — немає; цифрові покупки — так |
| Privacy policy URL | `https://vladislavdrucok-tech.github.io/deepbounce/` (після публікації сторінки) |

## Джерела для звірки
- Google Mobile Ads SDK: https://developers.google.com/admob/android/privacy/play-data-disclosure
- UMP: https://developers.google.com/admob/android/privacy
- Play Games Services: https://developers.google.com/games/services/console/enabling (розділ про Data safety)
- Правила Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
