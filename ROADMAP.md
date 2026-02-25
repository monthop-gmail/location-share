# 🗺️ ROADMAP: location-share

PWA แชร์ตำแหน่งแบบเรียลไทม์สำหรับกลุ่ม LINE — deploy บน Cloudflare Pages

---

## Phase 1: Foundation (✅ Done)
- ✅ สร้าง repo และโครงสร้างพื้นฐาน
- ✅ หน้าเว็บหลักพร้อมแผนที่ (Leaflet + OpenStreetMap)
- ✅ ปุ่ม 'แชร์ตำแหน่งของฉัน' และ 'ดูตำแหน่งเพื่อน'
- ✅ Deploy ได้ผ่าน Cloudflare Pages

## Phase 2: Realtime Sync
- เชื่อม Supabase Realtime Database
- Table `locations`: `user_id`, `lat`, `lng`, `updated_at`, `expires_at` (15 นาที)
- Auto-delete ตำแหน่งเก่าผ่าน Supabase function

## Phase 3: LINE Integration
- รองรับ LINE Login (`@line/liff`)
- แสดงชื่อและ avatar จาก LINE Profile
- จำกัดการดูตำแหน่งเฉพาะกลุ่มที่มี `group_id`

## Phase 4: UX & Security
- แจ้งสถานะ GPS (อนุญาต/ปฏิเสธ/ไม่รองรับ)
- แสดง timestamp ตำแหน่งล่าสุด
- ตั้งค่า Row Level Security (RLS) บน Supabase

## Phase 5: Production Ready
- ตั้งค่า branch protection: ต้องมี approval + CI pass ก่อน merge
- เอกสารการใช้งาน (ภาษาไทย)
- ลิงก์ issue tracker และ support

---

### ✅ Success Criteria
- ผู้ใช้ 2+ คนเปิดเว็บพร้อมกัน → มองเห็นตำแหน่งกันแบบ real-time ภายใน < 3 วินาที
- ไม่มี backend code ที่ต้องจัดการเอง (ใช้แค่ Cloudflare Pages + Supabase)
- ใช้งานได้บน LINE Browser, Chrome, Safari

### 📅 Timeline (ประมาณการ)
- Phase 2: ภายใน 1 วัน
- Phase 3–5: ภายใน 3 วัน
