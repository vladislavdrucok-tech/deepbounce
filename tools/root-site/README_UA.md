# Кореневий сайт розробника (для app-ads.txt)

AdMob перевіряє `app-ads.txt` **лише в корені домену**, вказаного як «Веб-сайт» у Google Play:
`https://vladislavdrucok-tech.github.io/app-ads.txt`. Сторінка гри `…github.io/deepbounce/` — це підпапка,
тому потрібен окремий **публічний** репозиторій GitHub Pages з назвою рівно `vladislavdrucok-tech.github.io`.
Основний сайт `deepbounce` (політика й умови) при цьому не змінюється.

1. AdMob → Settings → Account information → **Publisher ID** (`pub-` + 16 цифр).
2. `tools/root-site/make_app_ads.sh pub-XXXXXXXXXXXXXXXX` → тека `tools/root-site/out/` з трьома файлами:
   `app-ads.txt` (рядок `google.com, pub-…, DIRECT, f08c47fec0942fa0`), `index.html` (посилання на політику,
   умови й пошту підтримки), `.nojekyll`.
3. GitHub → New repository → назва `vladislavdrucok-tech.github.io`, **Public** → завантажити ці 3 файли в корінь
   гілки `main`.
4. Repository → Settings → Pages → Source: *Deploy from a branch* → `main` / `(root)` → Save.
5. Перевірити (до ~10 хв): `https://vladislavdrucok-tech.github.io/app-ads.txt` відкривається як текст.
6. Play Console → Deep Bounce → Grow users → Store presence → **Store settings** → Website:
   `https://vladislavdrucok-tech.github.io`.
7. AdMob → Apps → Deep Bounce → **app-ads.txt** → Check for updates (перевірка до 24 год, іноді кілька днів).

Тека `out/` у git не потрапляє: справжній pub-ID вписується лише під час створення файлу.
