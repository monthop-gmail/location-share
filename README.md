# location-share

PWA แชร์ตำแหน่งแบบเรียลไทม์สำหรับกลุ่ม LINE — deploy บน Cloudflare Pages + Supabase

**เปิดแอป:** https://location-share.pages.dev

📖 [คู่มือผู้ใช้ (USER_GUIDE.md)](docs/USER_GUIDE.md)

## Features

- **Realtime Location Sharing** — แชร์ตำแหน่ง GPS แบบเรียลไทม์ อัปเดตอัตโนมัติ
- **Friend List** — รายชื่อเพื่อน online/offline พร้อมค้นหาชื่อ
- **Navigation** — กดนำทางไปหาเพื่อนผ่าน Google Maps
- **Room/Group** — แยกห้องด้วย `#ชื่อห้อง` ต่อท้าย URL (รองรับภาษาไทย)
- **Route Drawing** — วาดเส้นทางบนแผนที่ แชร์ให้ทุกคนในห้องแบบ realtime
- **Destination Pin** — ปักหมุดจุดหมาย/ปลายทาง เลือก icon นำทางผ่าน Google Maps
- **Security** — XSS prevention, allowlist rendering, geographic boundary filter, DB constraints, Supabase RLS
- **PWA** — ติดตั้งลงหน้าจอได้ ใช้งานต่อได้ตอนเน็ตหลุด รองรับ LINE Browser, Chrome, Safari ไม่ต้อง login

## Tech Stack

- **Frontend:** HTML + CSS + JS (ไม่ใช้ framework), Leaflet, Leaflet-Draw
- **Database:** Supabase (PostgreSQL + Realtime)
- **Deploy:** Cloudflare Pages (auto-deploy on push to `main`)
- **CI/CD:** GitHub Actions

## Quick Start

```bash
git clone https://github.com/monthop-gmail/location-share.git
cd location-share
# แก้ไข SUPABASE_URL และ SUPABASE_ANON_KEY ใน index.html
# รัน SQL ตาม docs/MIGRATE.md ให้ครบก่อน
# push ไปยัง main branch → auto-deploy
```

## Database Setup

`migrations/*.sql` รันอัตโนมัติก่อน deploy ทุกครั้งที่ push เข้า `main`
ต้องตั้ง secret `SUPABASE_DB_URL` ก่อน ไม่งั้น deploy จะล้ม — ดู [MIGRATE.md](docs/MIGRATE.md)

ตั้งใหม่จากศูนย์ → [db_schema.sql](docs/db_schema.sql)

## Tests

```bash
node tests/smoke.js       # inline script ของ index.html บน browser stub
tests/migrations.sh       # ต้องมี DATABASE_URL ชี้ไป Postgres ที่ทิ้งได้
```

`smoke.js` จับ error ตอน init และตรวจว่าค่าจาก database ไม่หลุดเข้า DOM แบบไม่กรอง
`migrations.sh` โหลด schema แบบที่ production เป็นอยู่ แล้วรัน `migrations/` สองรอบ
เพื่อพิสูจน์ว่ารันซ้ำได้ — CI รันทั้งคู่ให้ทุก push

## Security

ดู [SECURITY.md](docs/SECURITY.md) — สรุปว่ากันอะไรได้ กันอะไรไม่ได้
และชื่อห้องทำหน้าที่เป็นความลับเพียงอย่างเดียวที่มีอยู่ตอนนี้

## Links

- **เว็บไซต์:** https://location-share.pages.dev
- **CI/CD:** [GitHub Actions](https://github.com/monthop-gmail/location-share/actions)
- **แผนงาน:** [ROADMAP.md](docs/ROADMAP.md)
- **ความปลอดภัย:** [SECURITY.md](docs/SECURITY.md)
- **แจ้งปัญหา:** [Issues](https://github.com/monthop-gmail/location-share/issues)
