# migrations/

**ทุกไฟล์ในโฟลเดอร์นี้ถูกรันกับ database จริงโดยอัตโนมัติ** ตามลำดับชื่อไฟล์
ก่อน deploy ทุกครั้งที่ push เข้า `main` (ดู `.github/workflows/deploy.yml`)

## กติกาของไฟล์ที่วางไว้ที่นี่

1. **ต้องรันซ้ำได้** — ไฟล์ทั้งหมดถูกรันใหม่ทุก push ไม่ใช่แค่ครั้งแรก
   ใช้ `IF NOT EXISTS`, `DROP ... IF EXISTS` ก่อน `CREATE`, `NOT VALID` กับ CHECK
2. **ต้องไม่ต้องพึ่งการไปกดอะไรใน Dashboard ก่อน** — ถ้าต้อง ให้เก็บไว้ใน `docs/` แทน
3. **ต้องทนกับ extension ที่ไม่มี** — ห่อด้วย `DO $$ ... EXCEPTION` แล้ว `RAISE WARNING`
   ดีกว่าทำให้ deploy ทั้งชุดล้ม (ดูตัวอย่างที่ `003_cleanup_cron.sql`)
4. **ลำดับใน `ALTER` สำคัญพอๆ กับลำดับไฟล์** — เช่น `001` ต้องปลด unique เดิม
   ก่อน backfill ไม่งั้นข้อมูลจริงจะชนกันเอง

## ก่อน merge ทุกครั้ง

`tests/migrations.sh` รันใน CI: โหลด schema แบบที่ production เป็นอยู่จริง
(`tests/baseline-schema.sql`) แล้วรัน `migrations/` สองรอบ และตรวจปลายทาง
รันเองได้ด้วย

```bash
docker run -d --rm --name pgtest -e POSTGRES_PASSWORD=test -e POSTGRES_DB=testdb postgres:16
docker run --rm --network container:pgtest -v "$PWD":/repo:ro \
  -e DATABASE_URL='postgres://postgres:test@127.0.0.1:5432/testdb' \
  postgres:16 bash /repo/tests/migrations.sh
docker stop pgtest
```

## ไฟล์ที่มีเงื่อนไขต้องทำก่อน

`004_row_ownership.sql` อยู่ในโฟลเดอร์นี้และรันอัตโนมัติเหมือนตัวอื่น แต่จะทำงาน
ถูกต้องก็ต่อเมื่อ **เปิด Anonymous Sign-ins ใน Dashboard แล้ว** และ **deploy client
ที่เรียก `signInAnonymously()` ไปแล้ว** ทั้งสองอย่างทำเสร็จก่อน merge PR ที่พาไฟล์นี้
เข้ามา — ลำดับนี้บังคับด้วยการแยกเป็นคนละ PR ไม่ใช่ด้วยโค้ด ดู `docs/SECURITY.md`

ถ้า merge ก่อนครบเงื่อนไข client จะเขียนข้อมูลไม่ได้ (อ่านได้ปกติ) แก้ด้วยการ
เปิด provider แล้วให้ผู้ใช้โหลดหน้าใหม่ ไม่ต้อง rollback database
