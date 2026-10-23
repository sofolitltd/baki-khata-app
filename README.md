# বাকির খাতা (Baki Khata)

দোকানের পাওনা ও দেনার হিসাব রাখার অ্যান্ড্রয়েড অ্যাপ। Flutter, অফলাইন-ফার্স্ট (SQLite), চাইলে অনলাইন ব্যাকআপ ও সিঙ্ক।

- সাইট ও ডাউনলোড: https://baki-khata-api-silk.vercel.app
- সার্ভার (API): [sofolitltd/baki-khata-api](https://github.com/sofolitltd/baki-khata-api)

## সুবিধা
- পাওনা ও দেনার আলাদা খাতা, বাকি/জমার লেনদেন
- মেয়াদ ও রিমাইন্ডার নোটিফিকেশন, প্রতিদিন সকাল ৯টায় সারাংশ
- এক ট্যাপে কল ও তাগাদা এসএমএস
- রিপোর্ট ও পরিসংখ্যান
- ফোন নাম্বার + ৫ ডিজিটের PIN লগইন
- অফলাইনে চলে; ইন্টারনেট থাকলে সার্ভারে ব্যাকআপ ও সিঙ্ক

## চালানো
```bash
make run-e    # অ্যান্ড্রয়েড এমুলেটরে (সার্ভার: http://10.0.2.2:8080)
make run-d    # আসল ফোনে (Mac-এর LAN IP দিয়ে সার্ভারে)
make run      # লোকাল API সার্ভার চালু (../baki_khata_api দরকার)
```

সার্ভারের ঠিকানা বদলাতে: `flutter run --dart-define=API_URL=https://...`
রিলিজ বিল্ডে ডিফল্ট ঠিকানা [lib/config.dart](lib/config.dart)-এ।

## রিলিজ বিল্ড
`android/key.properties` (গিটে নেই) আর কীস্টোর থাকতে হবে, নইলে ডিবাগ কী দিয়ে সাইন হয়।

```bash
flutter build apk --release --split-per-abi
```

এরপর ভার্সন ট্যাগ (`vX.Y.Z`) দিয়ে GitHub Releases-এ APK আপলোড করা হয়।
