# Security

สรุปว่าแอปนี้ป้องกันอะไรได้ ป้องกันอะไรไม่ได้ และถ้าจะปิดช่องที่เหลือต้องแลกกับอะไร

---

## Threat model

`SUPABASE_ANON_KEY` ฝังอยู่ใน `index.html` และ**ต้อง**เป็นแบบนั้น — แอปไม่มี backend
และไม่มีระบบ login ใครเปิด View Source ก็ได้ key ไป ดังนั้นสมมติฐานตั้งต้นคือ:

> **ผู้ไม่หวังดีมี anon key อยู่ในมือแน่นอน**

ความปลอดภัยทั้งหมดจึงต้องอยู่ที่ RLS policy และ CHECK constraint ฝั่ง database
ไม่ใช่ที่การซ่อน key

---

## ปิดไปแล้ว

### Stored XSS ผ่าน `pins.icon` และ `routes.color`

เดิมโค้ด escape เฉพาะ `name` แต่เอา `icon` กับ `color` ยัดเข้า HTML ตรงๆ
คนที่มี anon key จึง INSERT หมุดที่ `icon` เป็น `<img src=x onerror=...>` ได้
แล้วทุกคนในห้องจะรัน script นั้นทันทีที่โหลดหมุด

ปิดสองชั้น:

| ชั้น | วิธี |
|---|---|
| ตอน render | `safeIcon()` allowlist จาก `PIN_ICONS`, `safeColor()` บังคับ `#rrggbb`, `safeCoord()` บังคับตัวเลข |
| ตอนเขียนลง DB | CHECK constraint ใน [`migrations/002_validation.sql`](../migrations/002_validation.sql) — `icon` ยาวไม่เกิน 8 ตัวและห้ามมี `< > & " '` |

ชั้น render อย่างเดียวก็พอกัน XSS แล้ว ส่วน constraint มีไว้ไม่ให้ข้อมูลขยะเข้าตารางตั้งแต่แรก

### ข้อมูลขยะและพิกัดนอกโลก

`migrations/002_validation.sql` บังคับ lat/lng ให้อยู่ในกรอบเดียวกับ `isInBounds()`,
จำกัดความยาวชื่อ/ชื่อห้อง, และบังคับให้ `routes.coordinates` เป็น array ของจุด 2–1000 จุด
ทั้งหมดใช้ `NOT VALID` จึงบังคับเฉพาะแถวใหม่ ไม่ไปล้มเพราะข้อมูลเดิม

### ทุกห้องเห็นข้อมูลกันหมด (บางส่วน)

เดิม client ยิง `.select('*')` เอาทุกแถวของทุกห้องมาแล้วค่อยกรองเอง
ตอนนี้ `room` เป็นคอลัมน์จริงและ query กรองที่ DB แล้ว
([`migrations/001_rooms.sql`](../migrations/001_rooms.sql)) — เครื่องแต่ละเครื่องจึงได้เฉพาะห้องตัวเอง

**แต่นี่แก้เรื่องปริมาณข้อมูล ไม่ใช่เรื่องสิทธิ์** อ่านหัวข้อถัดไป

---

## ยังปิดไม่ได้ (issue #3)

### ใครมี anon key ก็ SELECT ได้ทุกห้อง

RLS policy ของ `locations` ยังเป็น `FOR SELECT USING (true)` คนที่มี key
เขียน query เองก็ดึงพิกัดของทุกห้องได้ ไม่ต้องรู้ชื่อห้อง

**ทำไมไม่ใช้ RPC + `SECURITY DEFINER` แล้วปิด SELECT ตรงตาราง?**

เพราะ **Supabase Realtime ประเมิน RLS ด้วย role ของผู้ subscribe**
ถ้าถอนสิทธิ์ SELECT ของ `anon` ออกจากตาราง `postgres_changes` จะไม่ส่ง event
ให้เลย — แปลว่าแอปจะไม่ realtime อีกต่อไป ซึ่งเป็นหัวใจของแอปทั้งตัว
ทางนี้จึง**ไม่ใช่**ทางออก

### ใครมี anon key ก็ลบข้อมูลของคนอื่นได้

`FOR DELETE USING (true)` ทั้งสามตาราง ยิง request เดียวลบพิกัด/เส้นทาง/หมุด
ของทุกคนได้หมด

---

## ทางแก้ที่เหลือ: Anonymous Sign-ins

ทางเดียวที่ปิดสองข้อบนได้จริงโดยยังคง realtime ไว้ คือให้ทุกเครื่องมี identity จริง
ผ่าน Supabase Anonymous Sign-ins แล้วเขียน policy อิง `auth.uid()`

SQL พร้อมรันอยู่ที่ [`migrate-rls-owner.sql`](migrate-rls-owner.sql) แล้ว

**สิ่งที่ได้:** ตำแหน่งของใครแก้/ลบได้เฉพาะเจ้าของ — ปิดช่อง "ลบข้อมูลคนอื่น" ได้สนิท

**สิ่งที่ยังไม่ได้:** การอ่าน ยังต้องเปิด SELECT ไว้ให้ realtime ทำงาน
ถ้าจะปิดการอ่านข้ามห้องด้วย ต้องเพิ่มตาราง `room_members` แล้วเขียน policy เป็น
`USING (room IN (SELECT room FROM room_members WHERE user_id = auth.uid()))`
ซึ่งแปลว่าต้องมีขั้นตอน "เข้าห้อง" ก่อนถึงจะเห็นข้อมูล — เปลี่ยนพฤติกรรมแอปพอสมควร

**สิ่งที่ต้องแลก:**

1. ต้องเปิด Anonymous Sign-ins ใน Dashboard ก่อน (Authentication → Providers)
2. ต้อง deploy client ที่เรียก `auth.signInAnonymously()` **พร้อมกัน** กับการรัน SQL
   ไม่งั้น client เดิมจะเขียนข้อมูลไม่ได้เลย
3. ทุกเครื่องที่เปิดแอปจะสร้างแถวใน `auth.users` และไม่หายเอง ต้องตั้ง cron ล้าง
4. ถ้าผู้ใช้ล้าง site data จะกลายเป็นคนละ identity — หมุดเก่าที่ตัวเองสร้างจะลบไม่ได้อีก
   (จึงยังเปิด DELETE ของ routes/pins ให้คนในห้องไว้ตามเดิม)

โค้ดฝั่ง client ที่ต้องเพิ่ม:

```js
// ต้องรอให้ session พร้อมก่อนยิง query แรก
const { error: authError } = await supabaseClient.auth.signInAnonymously();
if (authError) console.error('Anonymous sign-in failed:', authError);
```

> ยังไม่ได้ใส่ไว้ใน `index.html` เพราะถ้า deploy ออกไปตอนที่ยังไม่ได้เปิด
> Anonymous Sign-ins ในโปรเจกต์ แอปจะพังทั้งตัว — เป็นการตัดสินใจที่ต้องทำพร้อมกัน
> ทั้งฝั่ง Dashboard และฝั่ง deploy

---

## หมายเหตุ: ชื่อห้องคือความลับเพียงอย่างเดียวที่มี

จนกว่าจะทำ `room_members` ชื่อห้องทำหน้าที่เหมือนรหัสผ่านที่แชร์กัน
ในทางปฏิบัติควร:

- ตั้งชื่อห้องให้เดายาก (`#ทริปเชียงใหม่-x7k2` ดีกว่า `#ทริป`)
- ไม่โพสต์ลิงก์พร้อม hash ในที่สาธารณะ
- เปลี่ยนชื่อห้องเมื่อทริปจบ

`getRoom()` ตัด `@` ออกจากชื่อห้องเสมอ เพราะเคยเป็นตัวคั่นระหว่าง user_id กับห้อง
ในสคีมาเดิม
