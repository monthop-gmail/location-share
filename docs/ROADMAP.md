# ROADMAP: location-share

PWA แชร์ตำแหน่งแบบเรียลไทม์สำหรับกลุ่ม LINE — deploy บน Cloudflare Pages + Supabase

---

## Phase 1: Foundation — Done

- [x] สร้าง repo และโครงสร้างพื้นฐาน
- [x] หน้าเว็บหลักพร้อมแผนที่ (Leaflet + OpenStreetMap)
- [x] ปุ่มแชร์/หยุดแชร์ตำแหน่ง
- [x] Deploy บน Cloudflare Pages (auto-deploy)

## Phase 2: Realtime Sync — Done

- [x] เชื่อม Supabase Realtime Database
- [x] Table `locations`: `user_id`, `lat`, `lng`, `display_name`, `updated_at`, `expires_at`
- [x] DB trigger: `updated_at` + `expires_at` ใช้ server time (ไม่ใช้ client clock)
- [x] Auto-refresh ทุก 10 วินาที + Realtime subscription

## Phase 3: Friend List & Navigation — Done

- [x] รายชื่อเพื่อน online/offline (threshold 15 นาที)
- [x] ค้นหาเพื่อน (ชื่อ / online / offline)
- [x] กดชื่อเพื่อน → zoom ไปหา
- [x] ปุ่มนำทาง Google Maps
- [x] Fit Zoom ดูเพื่อนทุกคน

## Phase 4: Room/Group — Done

- [x] แยกห้องด้วย `#ชื่อห้อง` ต่อท้าย URL
- [x] รองรับชื่อห้องภาษาไทย
- [x] hashchange handler (เปลี่ยนห้องไม่ต้อง reload)
- [x] แต่ละห้องเห็นเฉพาะคนในห้องเดียวกัน

## Phase 5: Route Drawing — Done

- [x] วาดเส้นทางบนแผนที่ (Leaflet-Draw)
- [x] บันทึกลง Supabase ตาราง `routes`
- [x] Realtime sync เส้นทาง
- [x] รายการเส้นทาง + ลบ + tap to zoom
- [x] แยกเส้นทางตาม room

## Phase 6: Security & Stability — Done

- [x] XSS prevention (`escapeHtml`)
- [x] Geographic boundary filter (lat 0-25, lng 90-115)
- [x] GPS error handling (Thai messages)
- [x] Supabase RLS (SELECT/INSERT/UPDATE/DELETE)
- [x] Cache-busting headers สำหรับ LINE Browser

## Phase 7: Documentation — Done

- [x] คู่มือผู้ใช้ภาษาไทย ([USER_GUIDE.md](USER_GUIDE.md))
- [x] DB schema ([db_schema.sql](db_schema.sql))
- [x] Migration guide ([MIGRATE.md](MIGRATE.md))

## Phase 8: Destination Pin — Done

- [x] ปุ่ม "ปักหมุดจุดหมาย" → กดแผนที่ → dialog ใส่ชื่อ + เลือก icon
- [x] 6 icons: ทั่วไป, ปลายทาง, จุดพัก, ปั๊ม, จอดรถ, โรงแรม
- [x] บันทึกลง Supabase ตาราง `pins` + Realtime sync
- [x] Pin list: zoom, นำทาง Google Maps, ลบ
- [x] แยกหมุดตาม room

## Phase 9: Hardening — Done

- [x] ปิด stored XSS ที่ `pins.icon` / `routes.color` (allowlist ตอน render)
- [x] CHECK constraint ฝั่ง DB — พิกัด, ความยาวชื่อ, รูปแบบสี, โครงสร้าง coordinates
- [x] ยก `room` ขึ้นเป็นคอลัมน์จริง กรองที่ DB แทนการดึงทุกห้องมากรองเอง
- [x] ตั้ง pg_cron ลบตำแหน่งหมดอายุ (ฟังก์ชันมีมานานแต่ไม่เคยถูกเรียก)
- [x] Reconcile marker ทุกรอบ poll — เพื่อนที่หยุดแชร์ไม่ค้างบนแผนที่อีก
- [x] เลิก rebuild รายชื่อเพื่อนทีละคน (เดิม O(N²) ทุก 10 วินาที)
- [x] เลิกสร้าง marker ตัวเองใหม่ทุก GPS tick — popup ไม่เด้งซ้ำระหว่างขับรถ
- [x] เปลี่ยนการกรองจาก "วันนี้" เป็นหน้าต่าง 12 ชม. — เพื่อนไม่หายตอนเที่ยงคืน
- [x] หยุด poll เมื่อสลับแอปออก (ประหยัดแบตขณะจับ GPS)
- [x] ย้าย state ทั้งหมดขึ้นบนสุด + boot ที่ล่างสุด ปิดโอกาสเกิด TDZ ซ้ำ
- [x] แทน `prompt()` ด้วย dialog ในหน้า (in-app browser บางตัวไม่แสดง `prompt()`)
- [x] Smoke test + CI ที่รันจริง (เดิมเป็น `echo "CI passed!"`)

## Phase 10: PWA — Done

- [x] `manifest.json` + icon 192/512 + maskable + apple-touch-icon
- [x] Service worker แบบ network-first (ไม่ cache-first เพื่อไม่ให้ LINE Browser ค้างเวอร์ชันเก่า)
- [x] `_headers` แยก cache ของ static asset ออกจาก app shell

---

## Open Issues

- [#3 Stricter RLS Policies](https://github.com/monthop-gmail/location-share/issues/3)
  — SQL พร้อมรันอยู่ที่ [migrate-rls-owner.sql](migrate-rls-owner.sql) แล้ว
  รอตัดสินใจเรื่องเปิด Anonymous Sign-ins ดู [SECURITY.md](SECURITY.md)
- [#8 Import GPS (SinoTrack CSV/GPX)](https://github.com/monthop-gmail/location-share/issues/8)
- [#9 Branch markers from API](https://github.com/monthop-gmail/location-share/issues/9)

## Closed Issues

- [#1 Route/Polyline Support](https://github.com/monthop-gmail/location-share/issues/1)
- [#2 Manual Location Picker](https://github.com/monthop-gmail/location-share/issues/2) (ปิด — ใช้ GPS อย่างเดียว, Multi-Group ทำแล้ว)
- [#4 Schema: DELETE policy + display_name](https://github.com/monthop-gmail/location-share/issues/4)
- [#5 Room switch refresh](https://github.com/monthop-gmail/location-share/issues/5)
- [#6 Cleanup dead code + console spam](https://github.com/monthop-gmail/location-share/issues/6)
- [#7 Destination Pin](https://github.com/monthop-gmail/location-share/issues/7)
