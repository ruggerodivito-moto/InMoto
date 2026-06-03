# InMoto — Installazione standalone (client esterno)

## Requisiti del client

| Cosa serve | Note |
|------------|------|
| Linux (qualsiasi distro) | Ubuntu/Debian consigliati |
| Connessione internet | Solo accesso a github.com e codemagic.io |
| iPhone connesso via cavo USB | Con Developer Mode attivo |
| Account Codemagic (gratuito) | codemagic.io — 500 min/mese gratis |
| Apple ID (gratuito) | Quello che hai già |

## NON serve

- Accesso a asr-busmanager.simongenova.local ✗
- Accesso a reti interne AMT ✗
- Apple Developer Program ($99/anno) ✗
- Mac ✗

---

## Installazione — 4 comandi

```bash
# 1. Estrai il pacchetto (o sei già qui se usi la chiavetta)
cd ~/inmoto          # o la cartella dove hai estratto lo ZIP

# 2. Installa strumenti di sistema (una volta sola)
bash vm_install/1_setup_vm.sh

# 3. Configura credenziali Codemagic
bash vm_install/2_configura.sh

# 4. Connetti iPhone via USB, poi:
bash vm_install/3_pair_e_installa.sh
```

Lo step 4 fa tutto da solo:
- fa il pairing con l'iPhone
- avvia il build su Codemagic (~15 min)
- scarica l'IPA firmato
- installa l'app sull'iPhone

---

## Cosa configurare nell'app dopo l'installazione

Apri InMoto → tab **Impostazioni**:

- **URL Server**: l'URL del server AMT Scanner (es. `https://asr-busmanager.simongenova.local`)
  → serve solo per sincronizzare nuovi itinerari, l'app funziona **offline** senza
- **API Key**: il valore di `MOTO_APP_API_KEY` nel file `/opt/amt_scanner/.env` del server

L'app include già **196 itinerari offline** — funziona anche senza configurare il server.

---

## Rinnovo certificato (ogni 7 giorni)

```bash
bash vm_install/4_installa_ipa.sh
```

Oppure installa SideStore sul telefono per il rinnovo automatico senza computer:
Safari su iPhone → https://sidestore.io
