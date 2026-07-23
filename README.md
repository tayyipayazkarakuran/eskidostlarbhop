# ESKIDOSTLAR BHOP

Counter-Strike 1.6 / ReHLDS bhop sunucusu. Timer, ekonomi, özel haritalar ve bağımsız web portalı.

Bu depo üç ana katmandan oluşur:

| Katman | Açıklama |
|---|---|
| **AMX Mod X eklentileri** | bhop_timer (fizik + zona + strafe + ekonomi), bhop_map_manager (RTV/nominate), bhop_surf_fix |
| **Oyun assetleri** | Bhop haritaları (.bsp/.res), knife skin modelleri (.mdl), WR sesleri (.wav), cubemap (.tga) |
| **Web portalı** | PHP 8.1+ standalone leaderboard; MySQL PDO + GoldSrc A2S UDP; JSON API, MOTD |

---

## İçindekiler

- [AMX Mod X eklentileri](#amx-mod-x-eklentileri)
- [Haritalar ve assetler](#haritalar-ve-assetler)
- [Web portalı](#web-portalı)
- [Sunucu kurulumu](#sunucu-kurulumu)
- [Geliştirme](#geliştirme)
- [Lisans](#lisans)

---

## AMX Mod X eklentileri

### bhop_timer (`addons/amxmodx/scripting/bhop_timer.sma`)

Ana timer eklentisi. ReAPI tabanlıdır ve aşağıdaki bileşenlerden oluşur:

| Bileşen | Görevi |
|---|---|
| `physics.inc` | Zıplama fizik motoru, FPS bağımsız hız hesaplaması, strafe/ön-ziplama tespiti |
| `physics_fixes.inc` | Surf fix, bhop zorluğu ayarı, anti-önyükleme |
| `zone_embedded.inc` | Start/stop/checkpoint zonları, özel bölge tipleri |
| `storage.inc` | MySQL PDO bağlantısı, best/record/log yazma, oyuncu profili |
| `economy.inc` | Credit sistemi, badge/level, market alışverişi, inventory |
| `badges.inc` | Badge eşikleri (Bronz I → Diamond II), progres sorgulama |
| `visualization.inc` | HUD göstergeleri, center text, spektrum bilgisi |
| `editor.inc` | Zona düzenleyici (oyun içi .res dosyası yazma) |
| `strafe_stats.inc` | Strafe istatistikleri, sync yüzdesi, gain/loss |
| `mpbhop.inc` | Multi-player bhop (yarış) desteği |

**AMX Mod X sürümü:** 1.9+  
**ReAPI sürümü:** 5.x

### bhop_map_manager (`addons/amxmodx/scripting/bhop_map_manager.sma`)

RTV (Rock the Vote) ve /nominate sistemi.

- `/rtv` — Oy içi harita değiştirme oylaması başlatır (%60 oy gereki)
- `/nominate` — Oy verme havuzuna harita adayı gösterir
- `/nextmap` — Sıradaki haritayı gösterir
- `/timeleft` — Haritada kalan süreyi gösterir
- Menü tabanlı arayüz, `bmod_menu_style.inc` ile uyumlu

### bhop_surf_fix (`addons/amxmodx/scripting/bhop_surf_fix.sma`)

GoldSrc surf motoru düzeltmesi. Yüzey kayma fiziğini ReAPI ile onarır.

### Konfigürasyon dosyaları (`addons/amxmodx/configs/`)

| Dosya | Açıklama |
|---|---|
| `bhop_timer.cfg` | Ana timer ayarları (hız sınırı, zone ayarları, ekonomik değerler) |
| `bhop_timer_private.cfg.example` | Özel sunucu ayarları (MySQL bilgileri) — asla commit etmeyin |
| `plugins-bhop_timer.ini` | AMX Mod X plugin aktivasyon listesi |
| `modules-bhop_timer.ini` | Gerekli modüller (ReAPI, MySQL) |
| `mpbhop.cfg` | Multi-player bhop ayarları |

---

## Haritalar ve assetler

### Özel haritalar (`bhop_maps/maps/`)

14 adet özel bhop haritası, zorluk seviyelerine göre:

| Harita | Zorluk | Özellik |
|---|---|---|
| `bhop_m_novice` | Başlangıç | Kısa rota, geniş zeminler |
| `bhop_m_novice2` | Başlangıç | Alternatif başlangıç rotası |
| `bhop_m_skill` | Orta | Standart skill rotası |
| `bhop_m_skill2` | Orta | İkinci skill rotası |
| `bhop_m_skill3` | Orta-İleri | Üçüncü skill rotası |
| `bhop_m_skill4` | Orta-İleri | Dördüncü skill rotası (özel .res dosyası) |
| `bhop_m_skill_pro` | İleri | Profesyonel skill rotası |
| `bhop_m_fire` | Orta | Ateş temalı harita |
| `bhop_m_factory` | Orta | Fabrika temalı harita |
| `bhop_m_lab` | Orta | Laboratuvar temalı harita (özel .res) |
| `bhop_m_temple` | Orta | Tapınak temalı (cubemap + özel .res) |
| `bhop_m_wild` | Orta | Vahşi batı temalı |
| `bhop_m_ramp` | Başlangıç | Rampa mekaniği öğrenme |
| `bhop_m_ramp_old` | Başlangıç | Eski rampa rotası |
| `bhop_m_ramp2` | Başlangıç | İkinci rampa rotası |
| `bhop_m_ramp_pro` | Orta | Profesyonel rampa rotası |
| `bhop_m_target` | Orta | Hedef/nişan mekaniği |

Her harita için `.txt` dosyası harita yapımcısı kredisi ve bilgilerini içerir. `.res` dosyası gerekli özel dosyaları (ses, model) tanımlar.

### Cubemap (`bhop_maps/gfx/env/`)

`bhop_m_temple` haritası için özel cubemap (6 yüz .tga).

### Sesler (`bhop_maps/sound/`)

- `bhop_m_skill2/anthemcollides.wav`
- `bhop_m_skill4/rokdahouse.wav`

### Knife skin modelleri (`models/knifes/`)

| Klasör | Model | Tip |
|---|---|---|
| `talon_ed/` | Talon bıçağı | Normal skin |
| `bayonet_ed/` | Bayonet bıçağı | Normal skin |
| `karambit_ed/` | Karambit bıçağı | Normal skin |
| `butterfly_ed/` | Butterfly bıçağı | Normal skin |
| `vipgold_ed/` | Altın bıçak | VIP skin |
| `vipm9_ed/` | M9 Bayonet | VIP skin |

Her skin için `v_knife.mdl` (1. person) ve `p_knife.mdl` (dünya modeli) bulunur.

### WR sesleri (`sound/ed/`)

Dünya rekoru kırıldığında çalan üç farklı ses efekti:
- `wr1.wav`, `wr2.wav`, `wr3.wav`

---

## Web portalı

Detaylı belgeler: [`website/README.md`](website/README.md)

Özet:

```
website/
├── index.php              # Front controller (routing)
├── router.php             # PHP built-in server router
├── config.php             # Yapılandırma (env + local file override)
├── config.local.example.php  # Örnek yerel yapılandırma (commit edilmez)
├── .htaccess              # Apache rewrite + güvenlik
├── assets/
│   ├── css/
│   │   ├── style.css      # Ana site stilleri (550 satır, responsive)
│   │   └── motd.css       # MOTD stilleri (27 satır)
│   ├── js/
│   │   └── app.js         # Canlı yenileme (20s aralık), map filter, copy
│   └── fonts/
│       ├── barlow-condensed-semibold.ttf  # Display font (OFL lisanslı)
│       ├── ibm-plex-mono-regular.ttf      # Monospace font (OFL lisanslı)
│       └── ibm-plex-mono-semibold.ttf     # Monospace font (OFL lisanslı)
├── src/
│   ├── DataClient.php     # Veri katmanı interface
│   ├── LocalDataClient.php # JSON API dispatcher (9 endpoint)
│   ├── Db.php             # MySQL PDO sorguları (best, records, player, market)
│   ├── A2S.php            # GoldSrc A2S UDP protokolü (socket/stream)
│   ├── Steam.php          # Steam XML profil sorgulama
│   ├── ApiController.php  # /api/* JSON çıktısı
│   ├── Pages.php          # Sayfa render (home, profile, badges, market)
│   ├── Motd.php           # Oyun içi MOTD sayfaları
│   ├── Layout.php         # HTML layout (header, footer, alert)
│   ├── Support.php        # Yardımcı fonksiyonlar (time, mode, catalog, badges)
│   └── bootstrap.php      # Otoload ve başlangıç
└── README.md              # Web portalı kurulum belgeleri
```

### Özellikler

- **Salt-okunur MySQL** — Timer plugin veri yazar, web yalnız okur
- **A2S UDP** — Oyun sunucusunu canlı sorgulama (oyuncu listesi, harita, online durumu)
- **20 saniye aralıklı canlı yenileme** — Oyun içi değişiklikler webde anlık görünür
- **JSON API** — `/api/status`, `/api/pro15`, `/api/maps`, `/api/best-records`, `/api/player`, `/api/top-credits`, `/api/market`, `/api/badges`, `/api/live-ticker`
- **Tam responsive** — 560px → 1440px+ arası tüm ekranlar
- **Oyun içi MOTD** — `/motd?view=pro15|badges|topcredits|profile`
- **Ekonomi profilleri** — Credit bakiyesi, badge progresi, inventory görüntüleme

### Hızlı başlangıç (web)

```powershell
cd website
Copy-Item config.local.example.php config.local.php
# config.local.php içinde MySQL ve sunucu bilgilerini düzenleyin
php -d extension=sockets -S 127.0.0.1:18082 router.php
```

Ardından `http://127.0.0.1:18082` adresini açın.

---

## Sunucu kurulumu

1. **AMX Mod X 1.9+** ve **ReAPI 5.x** kurulu bir CS 1.6/ReHLDS sunucusu
2. `addons/amxmodx/` içindeki dosyaları sunucuya kopyalayın
3. `bhop_maps/maps/` içindeki `.bsp` dosyalarını `cstrike/maps/` klasörüne kopyalayın
4. Özel assetler (`models/`, `sound/`, `bhop_maps/gfx/`, `bhop_maps/sound/`) ilgili klasörlere kopyalayın
5. MySQL veritabanı oluşturun ve `bhop_timer.cfg` içindeki bağlantı bilgilerini ayarlayın
6. Web portalı için yukarıdaki adımları izleyin
7. Harita döngüsü için bir `mapcycle.txt` dosyası oluşturun

### Market sistemi

Oyun içi market, `bhop_timer` eklentisinin `economy.inc` bileşeni tarafından yönetilir. 16 ürünlük katalog:

| ID | Ürün | Fiyat | Tür |
|---|---|---|---|
| 1 | Custom Chat Prefix | 1.000 CR | custom_prefix |
| 2 | Custom Join Message | 500 CR | join_message |
| 10 | Talon Knife Skin | 2.000 CR | knife |
| 11 | Bayonet Knife Skin | 2.000 CR | knife |
| 12 | Karambit Knife Skin | 2.000 CR | knife |
| 13 | Butterfly Knife Skin | 2.000 CR | knife |
| 20 | VIP Gold Knife | 3.000 CR | vip_skin |
| 21 | VIP M9 Bayonet | 3.000 CR | vip_skin |
| 30–32 | WR Sound 1–3 | 1.500 CR | wrsound |
| 40–44 | Trail (5 renk) | 1.000 CR | trail |

---

## Geliştirme

### Bağımlılıklar

- **AMX Mod X 1.9+** — `amxmodx`, `amxmisc`, `fakemeta`, `cstrike`, `hamsandwich`
- **ReAPI 5.x** — `reapi` (`reapi.inc` ve alt modülleri)
- **MySQL** — Eklenti MySQL veritabanı kullanır (`storage.inc`)
- **PHP 8.1+** — Web portalı için
- **MySQL 5.7+/MariaDB 10.3+** — Web portalı için

### Derleme

AMX Mod X eklentilerini derlemek için:

```bash
# amxxpc kullanarak
amxxpc bhop_timer.sma
amxxpc bhop_map_manager.sma
amxxpc bhop_surf_fix.sma
```

Derlenmiş `.amxx` dosyaları `addons/amxmodx/plugins/` klasörüne kopyalanır.

### Web portalı lint

```powershell
Get-ChildItem . -Recurse -Filter *.php | ForEach-Object { php -l $_.FullName }
```

### API uç noktaları

| Yöntem | Uç nokta | Açıklama |
|---|---|---|
| GET | `/api/status` | MySQL bağlantısı, A2S oyun durumu, şema uyumu |
| GET | `/api/maps` | Harita listesi + her mod için WR bilgisi |
| GET | `/api/pro15?limit=N` | En çok PB'ye sahip ilk N oyuncu |
| GET | `/api/best-records?map=X&mode=Y&limit=N` | Harita/mode göre sıralama |
| GET | `/api/live-ticker?limit=N` | Son N bitiriş (WR/PB/Finish) |
| GET | `/api/player/{authid}` | Oyuncu profili (bests, records, inventory) |
| GET | `/api/top-credits?limit=N` | Credit sıralaması |
| GET | `/api/market` | Market kataloğu |
| GET | `/api/badges` | Badge eşikleri |
| GET | `/api/steam-profile?steamid={64}` | Steam XML profil sorgusu |

---

## Lisans

Bu proje özel bir CS 1.6 bhop sunucusu içindir.

- **Barlow Condensed** fontu — SIL Open Font License 1.1 (Copyright 2017 The Barlow Project Authors)
- **IBM Plex Mono** fontu — SIL Open Font License 1.1 (Copyright © 2017 IBM Corp.)
- **Haritalar** — Zerotech (petersam1980@gmail.com) tarafından geliştirilmiştir
- **Bhop timer eklentisi** — Özel geliştirme, tüm hakları saklıdır
- **Knife skin modelleri** — Özel tasarım, tüm hakları saklıdır
- **WR ses efektleri** — Özel ses dosyaları, tüm hakları saklıdır
