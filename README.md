# location-share

PWA แชร์ตำแหน่งแบบเรียลไทม์สำหรับกลุ่ม LINE — deploy บน Cloudflare Pages + Supabase

**เปิดแอป:** https://location-share.pages.dev

📖 [คู่มือผู้ใช้ (USER_GUIDE.md)](USER_GUIDE.md)

## Features

- **Realtime Location Sharing** — แชร์ตำแหน่ง GPS แบบเรียลไทม์ อัปเดตอัตโนมัติ
- **Friend List** — รายชื่อเพื่อน online/offline พร้อมค้นหาชื่อ
- **Navigation** — กดนำทางไปหาเพื่อนผ่าน Google Maps
- **Room/Group** — แยกห้องด้วย `#ชื่อห้อง` ต่อท้าย URL (รองรับภาษาไทย)
- **Route Drawing** — วาดเส้นทางบนแผนที่ แชร์ให้ทุกคนในห้องแบบ realtime
- **Security** — XSS prevention, geographic boundary filter, Supabase RLS
- **PWA** — ใช้งานได้บน LINE Browser, Chrome, Safari ไม่ต้อง login

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
# push ไปยัง main branch → auto-deploy
```

## Database Setup

ดู [db_schema.sql](db_schema.sql) สำหรับ schema ทั้งหมด หรือ [MIGRATE.md](MIGRATE.md) สำหรับ migration ที่ต้องรัน

## Links

- **เว็บไซต์:** https://location-share.pages.dev
- **CI/CD:** [GitHub Actions](https://github.com/monthop-gmail/location-share/actions)
- **แผนงาน:** [ROADMAP.md](ROADMAP.md)
- **แจ้งปัญหา:** [Issues](https://github.com/monthop-gmail/location-share/issues)
