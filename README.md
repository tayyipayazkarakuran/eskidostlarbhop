# ESKIDOSTLAR BHOP

CS 1.6 bunny hop server — custom maps, timer plugin ve standalone web portal.

## Bileşenler

- **addons/amxmodx/** — CS 1.6 bhop sunucusu için AMX Mod X eklentileri
- **bhop_maps/** — Özel bhop haritaları (.bsp + .res + .txt)
- **models/**, **sound/** — Sunucu assetleri (knife skin, WR sesleri)
- **website/** — PHP 8 tabanlı leaderboard portalı (PDO + A2S)

## Hızlı başlangıç

```bash
cd website
cp config.local.example.php config.local.php
# config.local.php'yi düzenleyin
php -d extension=sockets -S 127.0.0.1:18082 router.php
```

Detaylı kurulum için [website/README.md](website/README.md) dosyasına bakın.
