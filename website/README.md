# ESKIDOSTLAR BHOP — standalone website

Tek başına çalışan PHP 8 portalı. Aynı uygulama:

- MySQL veritabanını PDO ile salt-okunur sorgular.
- CS 1.6/ReHLDS sunucusunu GoldSrc A2S UDP protokolüyle sorgular.
- Web portalını ve legacy `/motd` sayfalarını render eder.
- Canlı yenilemede kullanılan `/api/*` JSON uçlarını kendisi sunar.

`web3` veya başka bir web projesi çalıştırmak gerekmez. Timer eklentisi verileri mevcut MySQL tablolarına yazmaya devam eder; bu website yalnız okur.

## Gereksinimler

- PHP 8.1+
- `pdo_mysql`, `curl`, `json`, `mbstring` eklentileri
- A2S için PHP `sockets` eklentisi veya UDP destekli `stream_socket_client`
- MySQL 5.7+/MariaDB 10.3+
- Apache `mod_rewrite`, Nginx front-controller kuralı veya PHP geliştirme sunucusu

## 1. Salt-okunur MySQL kullanıcısı

MySQL yöneticisiyle aşağıdaki hesabı oluşturun. `WEB_SERVER_IP` kısmını website’in bağlanacağı sunucu IP’siyle değiştirin. MySQL ve website aynı makinedeyse `localhost` kullanın.

```sql
CREATE USER 'bhop_web_readonly'@'WEB_SERVER_IP'
IDENTIFIED BY 'GUCLU_BIR_PAROLA';

GRANT SELECT ON `bhop_timer`.*
TO 'bhop_web_readonly'@'WEB_SERVER_IP';

FLUSH PRIVILEGES;
```

Website şu tabloları bekler: `bhop_best`, `bhop_records`, `bhop_players`, `bhop_inventory`, `bhop_market_items`. Şemayı website oluşturmaz; `bhop_timer.amxx` şema/veri sahibidir.

MySQL uzak sunucudaysa ayrıca:

- MySQL `bind-address` ayarının website sunucusuna izin verdiğini,
- 3306/TCP güvenlik duvarının yalnız website sunucu IP’sine açık olduğunu,
- MySQL kullanıcısının host kısmının doğru olduğunu kontrol edin.

## 2. Yapılandırma

En kolay yöntem:

```powershell
Copy-Item config.local.example.php config.local.php
```

Sonra `config.local.php` içindeki değerleri değiştirin. Bu dosya `.gitignore` içindedir ve Apache tarafından doğrudan erişime kapatılmıştır.

Ortam değişkenleri kullanmak isterseniz bunlar `config.local.php` değerlerinden önceliklidir:

| Ortam değişkeni | Açıklama |
|---|---|
| `BHOP_DB_HOST` | MySQL adresi |
| `BHOP_DB_PORT` | MySQL portu, varsayılan `3306` |
| `BHOP_DB_DB` | Veritabanı adı |
| `BHOP_DB_USER` | Salt-okunur MySQL kullanıcı adı |
| `BHOP_DB_PASS` | MySQL parolası |
| `BHOP_DB_PREFIX` | Tablo prefix'i; production `bhop_`, 27016 test `bmod_test_27016_` |
| `BHOP_GAME_HOST` | A2S ile sorgulanacak CS 1.6 sunucusu |
| `BHOP_GAME_PORT` | Oyun/A2S UDP portu, varsayılan `27016` |
| `BHOP_PUBLIC_CONNECT` | Oyuncuya gösterilecek public `host:port` |
| `WEBSITE_BASE_URL` | Opsiyonel alt dizin, ör. `/bhop` |
| `APP_TIMEZONE` | Varsayılan `Europe/Istanbul` |
| `BHOP_STEAM_ENRICHMENT` | Profil adı/avatar sorgusu; varsayılan kapalı |

`BHOP_GAME_HOST` A2S için kullanılabilecek iç IP olabilir. Oyuncuya gösterilen bağlantı adresi her zaman ayrı `BHOP_PUBLIC_CONNECT` değeridir.

## 3. Yerel çalıştırma

```powershell
Copy-Item config.local.example.php config.local.php
# config.local.php değerlerini düzenleyin
php -d extension=sockets -S 127.0.0.1:18082 router.php
```

Ardından `http://127.0.0.1:18082` ve sağlık kontrolü için `http://127.0.0.1:18082/api/status` adresini açın.

## 4. Production routing

Apache için document root’u `website/` klasörüne yöneltin; `.htaccess` hazırdır.

Nginx için temel kural:

```nginx
location / {
    try_files $uri $uri/ /index.php?$query_string;
}

location ~ ^/(?:src|tests)/ {
    deny all;
}

location ~ /(?:config(?:\.local)?(?:\.example)?\.php|router\.php)$ {
    deny all;
}

location ~ \.php$ {
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_pass unix:/run/php/php8.3-fpm.sock;
}
```

## Kontroller

```powershell
Get-ChildItem . -Recurse -Filter *.php | ForEach-Object { php -l $_.FullName }
php tests/run.php
```

Minimum smoke seti:

```text
GET /
GET /api/status
GET /api/maps
GET /api/pro15
GET /profile/<encoded-SteamID2>
GET /badges
GET /market
GET /top-credits
GET /motd
GET /motd?map=<map>&mode=normal
```

`/api/status` içinde:

- `connected: true` MySQL bağlantısının çalıştığını,
- `schemaCompatible: true` gerekli tablo/sütunların bulunduğunu,
- `game.online: true` A2S UDP sorgusunun yanıt aldığını gösterir.

## Güvenlik

- Website hesabına yalnız `SELECT` yetkisi verin.
- Gerçek parolayı kaynak koduna veya `config.local.example.php` dosyasına yazmayın.
- `config.local.php` dosyasını paylaşmayın/commit etmeyin.
- MySQL 3306 portunu internete tamamen açmayın; yalnız website sunucusuna izin verin.
- Steam enrichment’i ihtiyaç yoksa kapalı tutun; MOTD hiçbir zaman Steam profili beklemez.

## Market kataloğu

Website, oyun eklentisinin güncel 16 ürünlük kataloğunu salt-okunur fallback olarak içerir. `bhop_market_items` tablosundaki aynı ID’ye sahip satırlar ad, fiyat, tür ve efekt değerini override eder. Eski 3-7 ID aralığı güncel 10-44 kataloğuyla değiştirildiği için web marketinde gösterilmez.
