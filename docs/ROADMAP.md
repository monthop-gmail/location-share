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

## Phase 11: Deploy & Migration Automation — Done

- [x] `migrations/*.sql` รันอัตโนมัติก่อน deploy ทุก push (`migrate` → `deploy` ผูก `needs:`)
- [x] ทุกไฟล์ใน `migrations/` ต้องรันซ้ำได้ — CI รันสองรอบพิสูจน์
- [x] `tests/migrations.sh` ซ้อม migration กับ schema แบบที่ production เป็นจริง
- [x] `db-preflight` ตรวจ connection string ตั้งแต่ตอน PR ไม่ใช่ตอน deploy ล้ม
- [x] แก้ `_headers` ที่ Cloudflare ต่อค่ากฎทับกันเอง (icon ไม่เคยถูก cache จริง)

## Phase 12: Row Ownership — Done

- [x] Anonymous Sign-ins — ทุกเครื่องมี `auth.uid()` โดยผู้ใช้ไม่ต้องสมัคร
- [x] `withSession()` re-auth เงียบๆ แล้วลองใหม่เมื่อ session หมดอายุ
- [x] stamp `owner` ทุกแถวจาก JWT ไม่ใช่จาก client
- [x] `locations` แก้/ลบได้เฉพาะเจ้าของ — anon key เปล่าเขียนหรือลบไม่ได้อีก
- [x] `routes`/`pins` เปิด DELETE ให้คนในห้องโดยตั้งใจ (วางแผนทริปร่วมกัน)
- [x] เทสต์ RLS แบบสวมบทสองเครื่องคนละ identity ทดสอบกับ production จริงแล้ว
- [x] `CLAUDE.md` บันทึกข้อจำกัดที่มองไม่เห็นจากโค้ด

## Phase 13: Stop-sharing Retention — Done

- [x] `is_sharing` + soft delete แทนการลบถาวรตอนกดหยุดแชร์
- [x] trigger แยกสองกรณี — แชร์อยู่ 15 นาที, หยุดแล้วเก็บ 24 ชม.
- [x] `updated_at` ไม่ขยับตอนหยุด ตำแหน่งจึงไม่ดูเหมือนเพิ่งอัปเดต
- [x] จุดแดง + "(หยุดแชร์แล้ว)" ในรายชื่อและ marker
- [x] โหมดผู้ดูแล `?admin=1` (เป็นสวิตช์แสดงผล ไม่ใช่การควบคุมสิทธิ์)
- [x] ให้ผู้ใช้เลือก "หยุดและลบตำแหน่งทิ้ง" ได้ และบอกตรงๆ ว่าเก็บไว้ 24 ชม.

---

## Open Issues

- [#8 Import เส้นทางจากเครื่อง GPS (GPX/KML)](https://github.com/monthop-gmail/location-share/issues/8)
- [#9 ดึงข้อมูลสาขาจาก API แสดงเป็น marker](https://github.com/monthop-gmail/location-share/issues/9)
- [#10 Traccar GPS tracker integration](https://github.com/monthop-gmail/location-share/issues/10)
- [#16 จำกัดการอ่านตามห้องด้วย `room_members`](https://github.com/monthop-gmail/location-share/issues/16)
  — ส่วนที่เหลือจาก #3 ดู [SECURITY.md](SECURITY.md)

## Closed Issues

- [#1 Route/Polyline Support](https://github.com/monthop-gmail/location-share/issues/1)
- [#2 Manual Location Picker](https://github.com/monthop-gmail/location-share/issues/2) (ปิด — ใช้ GPS อย่างเดียว, Multi-Group ทำแล้ว)
- [#3 Stricter RLS Policies](https://github.com/monthop-gmail/location-share/issues/3)
  (ปิดฝั่งเขียนด้วย Phase 12 — ฝั่งอ่านแยกไป #16)
- [#4 Schema: DELETE policy + display_name](https://github.com/monthop-gmail/location-share/issues/4)
- [#5 Room switch refresh](https://github.com/monthop-gmail/location-share/issues/5)
- [#6 Cleanup dead code + console spam](https://github.com/monthop-gmail/location-share/issues/6)
- [#7 Destination Pin](https://github.com/monthop-gmail/location-share/issues/7)
- [#11 Location history for admin](https://github.com/monthop-gmail/location-share/issues/11)
  (ทำเฉพาะ "เก็บตำแหน่งสุดท้าย" ตาม Technical Changes — เส้นทางย้อนหลังจริง
  ต้องแยกตารางใหม่ ยังไม่ได้ทำ)
