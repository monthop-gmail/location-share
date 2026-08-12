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

## ไฟล์ที่จงใจไม่อยู่ที่นี่

`docs/migrate-rls-owner.sql` ต้องเปิด Anonymous Sign-ins ใน Dashboard และต้อง
deploy client ที่เรียก `signInAnonymously()` พร้อมกัน — ถ้ารันอัตโนมัติตอนที่ยัง
ไม่ได้เปิด provider แอปจะเขียนข้อมูลไม่ได้เลย ดู `docs/SECURITY.md`
