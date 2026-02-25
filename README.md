# Template ระบบ opencode-line-playground สำหรับ วิจัย/พัฒนา ผ่าน OpenCode LINE Bot

## 🎯 Best Practice

### 1 Repo → 1 LINE Group
- สร้าง 1 LINE Group
- เชิญ member ทุกคนเข้า group
- เชิญ LINE OA `@onboard-opencode` (https://line.me/ti/p/@525vvsgv) เข้า group ด้วย

## 📋 Prompt สำหรับสร้าง Project ใหม่

```
ช่วยสร้าง repo ใหม่จาก GitHub Template โดยใช้คำสั่ง:
gh repo create monthop-gmail/opencode-line-playground-004 --template monthop-gmail/opencode-line-playground-template-000 --public --clone

จากนั้น:
1. แก้ไข projectName ใน .github/workflows/deploy.yml เป็นชื่อ repo ใหม่
2. ตั้งค่า branch protection ให้ main branch:
   - ต้องมี approval 1 คน
   - ต้อง CI pass ก่อน merge
3. สร้าง README.md แบบย่อ:
   - ชื่อ project
   - Quick Start (clone, commit, push)
   - CI/CD (link issue, auto deploy)
   - ลิงก์ติดต่อ issue
4. Commit และ push ทั้งหมด
```

## 📋 วิธีใช้งาน

### 1. สร้าง Project ใหม่
ส่ง prompt ข้างบนให้ OpenCode LINE Bot

### 2. ขั้นตอนหลังได้ Repo
```
1. สร้าง Cloudflare Pages project ใหม่ (ชื่อเดียวกับ repo)
2. เพิ่ม secrets CF_API_TOKEN, CF_ACCOUNT_ID ใน repo
3. Clone repo → เขียน code → Push → Auto deploy!
```

### 3. Workflow การทำงานใน Repo
```
1. สร้าง issue ใน repo
2. สร้าง branch จาก issue
3. เขียน code ใน branch
4. สร้าง PR (อย่าลืม link issue เช่น closes #123)
5. รอ CI pass + approval
6. Merge → Auto deploy ไป Cloudflare Pages
```

## 🔄 CI/CD
- **CI**: ต้อง link issue ใน PR
- **Deploy**: Auto deploy หลัง push main

## 📞 ติดต่อ
https://github.com/monthop-gmail/opencode-line/issues

