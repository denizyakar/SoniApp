#!/bin/bash

# --- ROOT KONTROLÜ ---
if [ "$EUID" -ne 0 ]; then
  echo "HATA: Bu scripti çalıştırmak için root yetkisi gerekiyor!"
  echo "Lütfen 'sudo ./yonetici.sh' şeklinde tekrar dene."
  exit 1
fi

# Log dosyasının adını belirleyelim
LOG_FILE="server.log"

# 1. Node.js'i başlat ve çıktıları log dosyasına yönlendir
echo "--- [1/2] Node.js başlatılıyor... ---"
node server.js > "$LOG_FILE" 2>&1 &
NODE_PID=$!

# Kısa bir süre bekle (Dosyanın oluşması ve Node'un oturması için)
sleep 2

# 2. Cloudflare servisini başlat
echo "--- [2/2] Cloudflare servisi başlatılıyor... ---"
systemctl start cloudflared.service

# Servis düzgün başladı mı kontrol et
if [ $? -eq 0 ]; then
    echo "----------------------------------------------------"
    echo "BAŞARILI: Sistem ayakta. Loglar aşağıda akıyor..."
    echo "Kapatmak için 'service down' yazıp Enter'a bas."
    echo "----------------------------------------------------"
    
    # Logları ekrana bas (Arka planda çalışır)
    tail -f "$LOG_FILE" &
    TAIL_PID=$!

    # Kullanıcıdan girdi bekleme döngüsü
    while true; do
        read -p "KOMUT BEKLENİYOR: " user_input
        if [ "$user_input" == "down" ]; then
            echo "--- Kapatma işlemi başlatılıyor... ---"
            
            systemctl stop cloudflared.service
            kill $NODE_PID
            kill $TAIL_PID
            
            echo "--- Her şey güvenli bir şekilde kapatıldı. ---"
            break
        fi
    done
else
    echo "!!! KRİTİK HATA: Cloudflare servisi başlatılamadı! !!!"
    kill $NODE_PID
    exit 1
fi
